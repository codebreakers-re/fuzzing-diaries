use libafl::{
    corpus::{Corpus, InMemoryCorpus, OnDiskCorpus},
    events::SimpleEventManager,
    executors::{ForkserverExecutor, StdChildArgs},
    feedback_and, feedback_or,
    feedbacks::{MaxMapFeedback, TimeFeedback, TimeoutFeedback},
    inputs::BytesInput,
    mutators::BitFlipMutator,
    observers::{ConstMapObserver, HitcountsMapObserver, TimeObserver},
    schedulers::QueueScheduler,
    stages::StdMutationalStage,
    state::{HasCorpus, StdState},
    monitors::SimpleMonitor as SimpleStats,
    Fuzzer, StdFuzzer,
};
use libafl_bolts::{
    current_nanos,
    rands::StdRand,
    shmem::{ShMem, ShMemProvider, StdShMemProvider},
    tuples::tuple_list,
    StdTargetArgs,
};
use std::path::PathBuf;
use std::time::Duration;

/// Size of coverage map shared between observer and executor
const MAP_SIZE: usize = 65536;

fn main() {
    //
    // Component: Corpus
    //

    // path to input corpus
    let corpus_dirs = vec![PathBuf::from("./corpus")];

    // Corpus that will be evolved, we keep it in memory for performance
    let input_corpus = InMemoryCorpus::<BytesInput>::new();

    // Corpus in which we store solutions (timeouts/hangs in this example),
    // on disk so the user can get them after stopping the fuzzer
    let timeouts_corpus =
        OnDiskCorpus::new(PathBuf::from("./timeouts")).expect("Could not create timeouts corpus");

    //
    // Component: Observe
    //

    // A Shared Memory Provider which uses `shmget`/`shmat`/`shmctl` to provide shared
    // memory mappings. The provider is used to ... provide ... a coverage map that is then
    // shared between the Observer and the Executor
    let mut shmem_provider = StdShMemProvider::new().unwrap();
    let mut shmem = shmem_provider.new_shmem(MAP_SIZE).unwrap();

    // save the shared memory id to the environment, so that the forkserver knows about it; the
    // StMemId is populated as part of the implementor of the ShMem trait
    unsafe {
        shmem
            .write_to_env("__AFL_SHM_ID")
            .expect("couldn't write shared memory ID");
    }

    // this is the actual shared map, as a &mut [u8]
    let shmem_map = shmem.as_mut();
    let mut shmem_map = shmem_map.try_into().expect("Failed to convert slice to array");

    // Create an observation channel using the coverage map; since MAP_SIZE is known at compile
    // time, we can use ConstMapObserver to speed up Feedback::is_interesting
    let edges_observer = HitcountsMapObserver::new(ConstMapObserver::<_, MAP_SIZE>::new(
        "shared_mem",
        &mut shmem_map,
    ));

    // Create an observation channel to keep track of the execution time and previous runtime
    let time_observer = TimeObserver::new("time");

    //
    // Component: Feedback
    //

    // This is the state of the data that the feedback wants to persist in the fuzzers's state. In
    // particular, it is the cumulative map holding all the edges seen so far that is used to track
    // edge coverage.
    // let feedback_state = MapFeedback::with_name("edges", &edges_observer);

    // A Feedback, in most cases, processes the information reported by one or more observers to
    // decide if the execution is interesting. This one is composed of two Feedbacks using a logical
    // OR.
    //
    // Due to the fact that TimeFeedback can never classify a testcase as interesting on its own,
    // we need to use it alongside some other Feedback that has the ability to perform said
    // classification. These two feedbacks are combined to create a boolean formula, i.e. if the
    // input triggered a new code path, OR, false.
    let mut feedback = feedback_or!(
        MaxMapFeedback::new(&edges_observer),
        TimeFeedback::new(&time_observer)
    );

    // create a new map feedback state with a history map of size MAP_SIZE which provides state
    // about the edges feedback for timeouts
    let mut objective = feedback_and!(
        // A TimeoutFeedback reports as "interesting" if the exits via a Timeout
        TimeoutFeedback::new(),
        // Combined with the requirement for new coverage over timeouts
        MaxMapFeedback::new(&edges_observer)
    );

    //
    // Component: State
    //

    // Creates a new State, taking ownership of all of the individual components during fuzzing
    let mut state = StdState::new(
        // random number generator with a time-based seed
        StdRand::with_seed(current_nanos()),
        input_corpus,
        timeouts_corpus,
        &mut feedback,
        &mut objective,
    ).unwrap();

    //
    // Component: Stats
    //

    // call println with SimpleStats::display as input to report to the terminal. introspection
    // feature flag can be added for additional stats
    let stats = SimpleStats::new(|s| println!("{}", s));

    //
    // Component: EventManager
    //

    // The event manager handles the various events generated during the fuzzing loop
    // such as the notification of the addition of a new testcase to the corpus
    let mut mgr = SimpleEventManager::new(stats);

    //
    // Component: Scheduler
    //

    // A minimization + queue policy to get test cases from the corpus
    //
    // IndexesLenTimeMinimizerCorpusScheduler is a MinimizerCorpusScheduler with a
    // LenTimeMulFavFactor that prioritizes quick and small Testcases that exercise all the

    // entries registered in the MapIndexesMetadata
    //
    // a QueueCorpusScheduler walks the corpus in a queue-like fashion
    let scheduler = QueueScheduler::new();

    //
    // Component: Fuzzer
    //

    // A fuzzer with feedback, objectives, and a corpus scheduler
    let mut fuzzer = StdFuzzer::new(scheduler, feedback, objective);

    //
    // Component: Executor
    //

    // Create the executor for the forkserver. The TimeoutForkserverExecutor wraps the standard
    // ForkserverExecutor and sets a timeout before each run. This gives us an executor
    // that implements an AFL-like mechanism that will spawn child processes to fuzz
    let mut executor = ForkserverExecutor::builder()
        .program("./xpdf/install/bin/pdftotext".to_string())
        .args(&[String::from("@@")])
        .shmem_provider(&mut shmem_provider)
        .timeout(Duration::from_millis(5000))
        .build(tuple_list!(edges_observer, time_observer))
        .unwrap();

    // In case the corpus is empty (i.e. on first run), load existing test cases from on-disk
    // corpus
    if state.corpus().count() < 1 {
        state
            .load_initial_inputs(&mut fuzzer, &mut executor, &mut mgr, &corpus_dirs)
            .unwrap_or_else(|err| {
                panic!(
                    "Failed to load initial corpus at {:?}: {:?}",
                    &corpus_dirs, err
                )
            });
        println!("We imported {} inputs from disk.", state.corpus().count());
    }

    //
    // Component: Mutator
    //

    // Setup a mutational stage with a basic bytes mutator
    let mutator = BitFlipMutator::new();

    //
    // Component: Stage
    //

    let mut stages = tuple_list!(StdMutationalStage::new(mutator));

    // start the fuzzing
    fuzzer
        .fuzz_loop(&mut stages, &mut executor, &mut state, &mut mgr)
        .expect("Error in the fuzzing loop");
}

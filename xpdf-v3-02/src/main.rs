use libafl::{
    corpus::{Corpus, InMemoryCorpus, OnDiskCorpus},
    events::SimpleEventManager,
    executors::{forkserver::ForkserverExecutor, HasObservers, StdChildArgs},
    feedback_and, feedback_and_fast, feedback_or, feedback_or_fast,
    feedbacks::{CrashFeedback, MaxMapFeedback, TimeFeedback, TimeoutFeedback},
    inputs::BytesInput,
    monitors::tui::TuiMonitor,
    mutators::{havoc_mutations, scheduled::HavocScheduledMutator, tokens_mutations, Tokens},
    observers::{CanTrack, ConstMapObserver, HitcountsMapObserver, StdMapObserver, TimeObserver},
    schedulers::{IndexesLenTimeMinimizerScheduler, QueueScheduler},
    stages::StdMutationalStage,
    state::{HasCorpus, StdState},
    Fuzzer, StdFuzzer,
};
use libafl_bolts::{
    current_nanos,
    rands::StdRand,
    shmem::{ShMem, ShMemProvider, UnixShMemProvider},
    tuples::{tuple_list, Handled, Merge},
    AsSliceMut, StdTargetArgs,
};
use std::path::PathBuf;
use std::time::Duration;

/// Size of coverage map shared between observer and executor
const MAP_SIZE: usize = 2097152;

fn main() {
    //
    // Component: Corpus
    //

    // path to input corpus
    let corpus_dirs = vec![PathBuf::from("./corpus")];

    // Check if corpus directory exists and has files
    if !corpus_dirs[0].exists() {
        panic!("Corpus directory does not exist: {:?}", corpus_dirs[0]);
    }
    if !corpus_dirs[0].is_dir() {
        panic!("Corpus path is not a directory: {:?}", corpus_dirs[0]);
    }

    let entries = std::fs::read_dir(&corpus_dirs[0])
        .expect("Failed to read corpus directory")
        .count();

    if entries == 0 {
        panic!("Corpus directory is empty: {:?}", corpus_dirs[0]);
    }

    println!(
        "Found {} files in corpus directory: {:?}",
        entries, corpus_dirs[0]
    );

    // Corpus that will be evolved, we keep it in memory for performance
    let input_corpus = InMemoryCorpus::<BytesInput>::new();

    // Corpus in which we store solutions (crashes in this example),
    // on disk so the user can get them after stopping the fuzzer
    let crashes_corpus =
        OnDiskCorpus::new(PathBuf::from("./crashes")).expect("Could not create crashes corpus");

    // Corpus for timeout cases - also stored on disk
    let timeouts_corpus: OnDiskCorpus<BytesInput> =
        OnDiskCorpus::new(PathBuf::from("./timeouts")).expect("Could not create timeouts corpus");

    //
    // Component: Observe
    //

    // A Shared Memory Provider which uses `shmget`/`shmat`/`shmctl` to provide shared
    // memory mappings. The provider is used to ... provide ... a coverage map that is then
    // shared between the Observer and the Executor
    let mut shmem_provider = UnixShMemProvider::new().unwrap();
    let mut shmem = shmem_provider.new_shmem(MAP_SIZE).unwrap();

    // save the shared memory id to the environment, so that the forkserver knows about it; the
    // StMemId is populated as part of the implementor of the ShMem trait
    unsafe { shmem.write_to_env("__AFL_SHM_ID").unwrap() }

    // this is the actual shared map, as a &mut [u8]
    let shmem_buf = shmem.as_slice_mut();
    // let mut shmem_map = shmem_buf
    //     .try_into()
    //     .expect("Failed to convert slice to array");
    //
    // Create an observation channel using the coverage map; since MAP_SIZE is known at compile
    // time, we can use ConstMapObserver to speed up Feedback::is_interesting
    let edges_observer = unsafe {
        HitcountsMapObserver::new(StdMapObserver::new("shared_mem", shmem_buf)).track_indices()
    };

    // Create an observation channel to keep track of the execution time and previous runtime
    let time_observer = TimeObserver::new("time");

    // Create feedback for corpus evolution - this determines which inputs get added to corpus
    // Use both coverage and timing feedback for better corpus evolution
    let mut feedback = feedback_and_fast!(
        // Track coverage increases - this allows corpus growth
        MaxMapFeedback::new(&edges_observer),
        // Prefer faster executions when coverage is similar
        TimeFeedback::new(&time_observer)
    );

    // Create feedback for objectives (crashes, timeouts) - these get saved to disk
    let mut objective = feedback_or_fast!(
        // CrashFeedback reports as "interesting" if the program crashes
        CrashFeedback::new(),
        // TimeoutFeedback reports as "interesting" if the program times out
        TimeoutFeedback::new()
    );

    //
    // Component: State
    //

    // Creates a new State, taking ownership of all of the individual components during fuzzing
    let mut state = StdState::new(
        // random number generator with a time-based seed
        StdRand::with_seed(current_nanos()),
        input_corpus,
        crashes_corpus,
        // States of the feedbacks that store the data related to the feedbacks that should be
        // persisted in the State.
        &mut feedback,
        &mut objective,
    )
    .unwrap();

    //
    // Component: Stats
    //

    // call println with SimpleStats::display as input to report to the terminal. introspection
    // feature flag can be added for additional stats
    let monitor = TuiMonitor::builder()
        .title("XPDF Fuzzer")
        .enhanced_graphics(false)
        .build();

    //
    // Component: EventManager
    //

    // The event manager handles the various events generated during the fuzzing loop
    // such as the notification of the addition of a new testcase to the corpus
    let mut mgr = SimpleEventManager::new(monitor);

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
    let scheduler = IndexesLenTimeMinimizerScheduler::new(&edges_observer, QueueScheduler::new());

    //
    // Component: Fuzzer
    //

    // A fuzzer with feedback, objectives, and a corpus scheduler
    let mut fuzzer = StdFuzzer::new(scheduler, feedback, objective);

    // let observer_ref = edges_observer.handle();

    // Check if the target binary exists before creating executor
    let target_binary = "./xpdf/install/bin/pdftotext";
    if !std::path::Path::new(target_binary).exists() {
        panic!("Target binary does not exist: {}", target_binary);
    }

    println!("Creating executor with command: {} {}", target_binary, "@@");

    let mut executor = ForkserverExecutor::builder()
        .program(target_binary.to_string())
        .parse_afl_cmdline(&["@@"])
        .debug_child(false) // disable stdout capture
        .shmem_provider(&mut shmem_provider)
        .timeout(Duration::from_millis(5000))
        .coverage_map_size(MAP_SIZE)
        .is_persistent(false) // ensure we're not in persistent mode
        .build(tuple_list!(edges_observer, time_observer))
        .unwrap();

    // In case the corpus is empty (i.e. on first run), load existing tecst cases from on-disk
    // corpus
    // if let Some(dynamic_map_size) = executor.coverage_map_size() {
    //     executor.observers_mut()[&observer_ref]
    //         .as_mut()
    //         .truncate(dynamic_map_size);
    // }

    if state.corpus().count() < 1 {
        println!("Loading initial corpus from {:?}...", &corpus_dirs);

        state
            .load_initial_inputs_forced(&mut fuzzer, &mut executor, &mut mgr, &corpus_dirs)
            .unwrap_or_else(|err| {
                panic!(
                    "Failed to load initial corpus at {:?}: {:?}",
                    &corpus_dirs, err
                )
            });

        if state.corpus().count() < 1 {
            panic!("Corpus is empty after loading - this is likely a bug")
        }

        println!(
            "Successfully imported {} inputs from disk.",
            state.corpus().count()
        );
        println!("Corpus loading complete. Starting fuzzing loop...");
    } else {
        println!(
            "Using existing corpus with {} inputs.",
            state.corpus().count()
        );
    }

    //
    // Component: Mutator
    //

    // Setup a mutational stage with a basic bytes mutator
    let mutator = HavocScheduledMutator::new(havoc_mutations());

    //
    // Component: Stage
    //

    let mut stages = tuple_list!(StdMutationalStage::new(mutator));

    // Print configuration summary
    println!("=== FUZZER CONFIGURATION ===");
    println!("Target: {}", target_binary);
    println!("Corpus: {} inputs loaded", state.corpus().count());
    println!("Feedback: Coverage + Timing");
    println!("Objectives: Crashes + Timeouts");
    println!("=============================");

    // start the fuzzing
    fuzzer
        .fuzz_loop(&mut stages, &mut executor, &mut state, &mut mgr)
        .expect("Error in the fuzzing loop");
}

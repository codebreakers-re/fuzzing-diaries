{ pkgs, lib, config, inputs, ... }:

{
  # https://devenv.sh/basics/
  env.GREET = "devenv";

  # https://devenv.sh/packages/
  packages = [ 
	  pkgs.git 
	  pkgs.aflplusplus 
	  pkgs.wget
  ];

  # https://devenv.sh/languages/
  languages.rust = {
	  enable = true;
	  channel="stable";
  };
  

  # https://devenv.sh/processes/
  # processes.cargo-watch.exec = "cargo-watch";

  # https://devenv.sh/services/
  # services.postgres.enable = true;

  # https://devenv.sh/scripts/
  tasks = {
  	"bash:download_xpdf" = {
	  exec = ''
	  wget https://dl.xpdfreader.com/old/xpdf-3.02.tar.gz
	  tar xvf xpdf-3.02.tar.gz
	  rm xpdf-3.02.tar.gz
	  mv xpdf-3.02 xpdf
	  '';

	};

	"bash:make_xpdf" = {
		exec = ''
		  $DEVENV_ROOT
	  ''
	  };


  };


  scripts.corpus.exec = ''
  mkdir corpus
  cd corpus
  wget https://github.com/mozilla/pdf.js-sample-files/raw/master/helloworld.pdf
  wget http://www.africau.edu/images/default/sample.pdf
  wget https://www.melbpc.org.au/wp-content/uploads/2017/10/small-example-pdf-file.pdf
  '';


  enterShell = ''
    git --version
  '';


  # https://devenv.sh/tests/
  enterTest = ''
    echo "Running tests"
    git --version | grep --color=auto "${pkgs.git.version}"
  '';

  # https://devenv.sh/git-hooks/
  # git-hooks.hooks.shellcheck.enable = true;

  # See full reference at https://devenv.sh/reference/options/
}

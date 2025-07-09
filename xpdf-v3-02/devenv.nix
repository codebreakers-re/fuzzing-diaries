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
	  if [ -d "xpdf" ]; then
	    rm -r xpdf 
	  fi
	  
	  wget https://dl.xpdfreader.com/old/xpdf-3.02.tar.gz
	  tar xf xpdf-3.02.tar.gz
	  rm xpdf-3.02.tar.gz
	  mv xpdf-3.02 xpdf
	  '';
	};

	"bash:corpus" = {
	exec = ''
	  if [ -d "corpus" ]; then
	    rm -r corpus
	  fi

	  mkdir corpus
	  cd corpus
	  
	  wget --timeout=5 --tries=2 https://www.melbpc.org.au/wp-content/uploads/2017/10/small-example-pdf-file.pdf || echo "Failed to download small example PDF"
	  wget --timeout=5 --tries=2 https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf || echo "Failed to download dummy PDF"
	  wget --timeout=5 --tries=2 https://www.irs.gov/pub/irs-pdf/f1040.pdf -O irs-form-1040.pdf || echo "Failed to download IRS form"
	  wget --timeout=5 --tries=2 https://www.w3.org/TR/2008/REC-xml-20081126/REC-xml-20081126.pdf -O w3c-xml-spec.pdf || echo "Failed to download W3C XML spec"
	  wget --timeout=5 --tries=2 https://www.unicode.org/reports/tr15/tr15-53.pdf -O unicode-tr15.pdf || echo "Failed to download Unicode TR15"
	  wget --timeout=5 --tries=2 https://www.rfc-editor.org/rfc/rfc2616.pdf -O rfc2616-http.pdf || echo "Failed to download RFC 2616"
	  wget --timeout=5 --tries=2 https://www.ecma-international.org/wp-content/uploads/ECMA-262_6th_edition_june_2015.pdf -O ecma262-es6.pdf || echo "Failed to download ECMA-262 ES6"
	  wget --timeout=5 --tries=2 https://www.iso.org/files/live/sites/isoorg/files/store/en/PUB100080.pdf -O iso-pub.pdf || echo "Failed to download ISO publication"
	  wget --timeout=5 --tries=2 https://www.unicode.org/versions/Unicode15.0.0/UnicodeStandard-15.0.pdf -O unicode-15.0.pdf || echo "Failed to download Unicode 15.0"
	  wget --timeout=5 --tries=2 https://www.ecma-international.org/wp-content/uploads/ECMA-262_5th_edition_december_2009.pdf -O ecma262-es5.pdf || echo "Failed to download ECMA-262 ES5"
	  wget --timeout=5 --tries=2 https://www.unicode.org/charts/PDF/U0000.pdf -O unicode-basic-latin.pdf || echo "Failed to download basic latin chart"
	  wget --timeout=5 --tries=2 https://www.unicode.org/charts/PDF/U0080.pdf -O unicode-latin1-supplement.pdf || echo "Failed to download latin1 supplement chart"
	  wget --timeout=5 --tries=2 https://www.unicode.org/charts/PDF/U0100.pdf -O unicode-latin-extended-a.pdf || echo "Failed to download latin extended-a chart"
	  wget --timeout=5 --tries=2 https://www.unicode.org/charts/PDF/U0370.pdf -O unicode-greek-coptic.pdf || echo "Failed to download greek coptic chart"
	  wget --timeout=5 --tries=2 https://www.unicode.org/charts/PDF/U0400.pdf -O unicode-cyrillic.pdf || echo "Failed to download cyrillic chart"
	  wget --timeout=5 --tries=2 https://www.unicode.org/charts/PDF/U4E00.pdf -O unicode-cjk-ideographs.pdf || echo "Failed to download CJK ideographs chart"
	  wget --timeout=5 --tries=2 https://www.unicode.org/charts/PDF/U0590.pdf -O unicode-hebrew.pdf || echo "Failed to download hebrew chart"
	  wget --timeout=5 --tries=2 https://www.unicode.org/charts/PDF/U0600.pdf -O unicode-arabic.pdf || echo "Failed to download arabic chart"
	  wget --timeout=5 --tries=2 https://www.unicode.org/charts/PDF/U0900.pdf -O unicode-devanagari.pdf || echo "Failed to download devanagari chart"
	  wget --timeout=5 --tries=2 https://www.unicode.org/charts/PDF/U2000.pdf -O unicode-punctuation.pdf || echo "Failed to download punctuation chart"
	'';

	};

	 "bash:make_xpdf" = {
		exec = ''
		  cd xpdf
		  
		  if [ -d "install" ]; then
		    make clean
		    rm -r install
		  fi
		  
		  ./configure --prefix=$DEVENV_ROOT/xpdf/install
		  make
		  make install
	  '';
	  };
	  "bash:cargo_build" = {
	  	exec = ''
		  cargo build
		'';

	  };

	  "bash:build_fuzzer" = {
	  	exec = ''
		  cargo build --release
		'';

	  };

  };



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

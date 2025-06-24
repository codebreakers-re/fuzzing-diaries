{ config, ... }: {
  programs.nixvim = {
    enable = true;
    globals.mapleader = " ";
    colorschemes.catppuccin.enable = true;
    dependencies = {
	ripgrep.enable = true;
	rust-analyzer.enable = true;
    };
    plugins = {
    	    mini.modules.icons.enable = true;
	    lualine.enable = true;
	    lspconfig.enable = true;
	    telescope = { 
	    	    keymaps = {
			  "<leader>sg" = "live_grep";
			  "<leader>sf" = "find_files";
			  "<leader>ss" = "builtin";

		    };
		    enable = true;
		    extensions = {
		      file-browser = {
			enable = true;
		      };
		      ui-select = {
			enable = true;
		      };
		      frecency = {
			enable = true;
			settings.disable_devicons = true;
		      };
		      fzf-native = {
			enable = true;
		      };
		    };

	    };
	    fzf-lua.enable = true;
	    oil = { 
		    enable = true; 
		    autoLoad = true;
	    };
    };
	lsp = {

		inlayHints.enable = true;
		keymaps = [
		  {
		    key = "gd";
		    lspBufAction = "definition";
		  }
		  {
		    key = "gD";
		    lspBufAction = "references";
		  }
		  {
		    key = "gt";
		    lspBufAction = "type_definition";
		  }
		  {
		    key = "gi";
		    lspBufAction = "implementation";
		  }
		  {
		    key = "K";
		    lspBufAction = "hover";
		  }
		  {
		    action = "<CMD>LspStop<Enter>";
		    key = "<leader>lx";
		  }
		  {
		    action = "<CMD>LspStart<Enter>";
		    key = "<leader>ls";
		  }
		  {
		    action = "<CMD>LspRestart<Enter>";
		    key = "<leader>lr";
		  }
		  {
		    action = config.lib.nixvim.mkRaw "require('telescope.builtin').lsp_definitions";
		    key = "gd";
		  }
		  {

		    action = config.lib.nixvim.mkRaw "function() vim.diagnostic.jump({ count=-1, float=true }) end";
		    key = "<leader>k";
		  }
		  {
		    action = config.lib.nixvim.mkRaw "function() vim.diagnostic.jump({ count=1, float=true }) end";
		    key = "<leader>j";
		  }
		  {
		    action = "<CMD>Lspsaga hover_doc<Enter>";
		    key = "K";
		  }
		];
		servers = { 
		"*" = {
		    settings = {
		      capabilities = {
			textDocument = {
			  semanticTokens = {
			    multilineTokenSupport = true;
			  };
			};
		      };
		      root_markers = [
			".git"
		      ];
		    };
		  };
			clangd.enable = true;
			rust_analyzer.enable = true;
			nixd.enable = true;
		};
	};
    };
}

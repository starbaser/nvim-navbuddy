{
  description = "navbuddy: keyboard-centric breadcrumb navigator for Neovim";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";

    gen-luarc = {
      url = "github:mrcjkb/nix-gen-luarc-json";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    nixpkgs,
    flake-utils,
    gen-luarc,
    ...
  }:
    flake-utils.lib.eachDefaultSystem (system: let
      pkgs = (nixpkgs.legacyPackages.${system}).extend gen-luarc.overlays.default;

      vimPlugin = pkgs.vimUtils.buildVimPlugin {
        pname = "nvim-navbuddy";
        version = "0-unstable";
        src = pkgs.lib.fileset.toSource {
          root = ./.;
          fileset = pkgs.lib.fileset.unions [
            ./lua
            ./doc
          ];
        };
        dependencies = with pkgs.vimPlugins; [
          nui-nvim
          nvim-lspconfig
          nvim-navic
        ];
      };

      luarc = pkgs.mk-luarc {
        nvim = pkgs.neovim-unwrapped;
        lua-version = "jit51";
        plugins = with pkgs.vimPlugins; [
          nui-nvim
          nvim-navic
          telescope-nvim
          snacks-nvim
          comment-nvim
          mini-nvim
        ];
      };

      luarcJson = pkgs.luarc-to-json (luarc
        // {
          diagnostics =
            luarc.diagnostics
            // {
              unusedLocalExclude = ["_*"];
            };
        });
    in {
      packages = {
        default = vimPlugin;
        inherit vimPlugin;
      };

      devShells.default = pkgs.mkShell {
        packages = with pkgs; [
          lua-language-server
          stylua
          just
        ];

        shellHook = ''
          ln -fs ${luarcJson} .luarc.json
        '';
      };
    });
}

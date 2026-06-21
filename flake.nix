{
  description = "Personal multi-device home-manager config";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, home-manager, ... }:
    let
      mkHome = { system, username, homeDirectory }:
        home-manager.lib.homeManagerConfiguration {
          pkgs = import nixpkgs { inherit system; config.allowUnfree = true; };
          # Module list lives in lib/default.nix.
          modules = (import ./lib).modules ++ [
            { home.username = username; home.homeDirectory = homeDirectory; }
          ];
        };
    in {
      homeConfigurations = {
        # Generic profile; needs --impure for current user/home/system.
        "generic" = mkHome {
          system        = builtins.currentSystem;
          username      = builtins.getEnv "USER";
          homeDirectory = builtins.getEnv "HOME";
        };

        # Add named profiles only when a host needs divergent settings.
      };

      # Project devShell templates.
      templates = {
        python = { path = ./modules/dev-envs/templates/python; description = "Python dev shell (python3 + uv)"; };
        node = { path = ./modules/dev-envs/templates/node; description = "Node.js dev shell (nodejs_22 + pnpm)"; };
        rust = { path = ./modules/dev-envs/templates/rust; description = "Rust dev shell (rustc + cargo + rust-analyzer)"; };
        go = { path = ./modules/dev-envs/templates/go; description = "Go dev shell (go + gopls)"; };
        generic = { path = ./modules/dev-envs/templates/generic; description = "Generic dev shell (add tools to buildInputs)"; };
      };
    };
}

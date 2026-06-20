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
          # 模块列表从 lib/default.nix 取(唯一的"加模块"改动点)
          modules = (import ./lib).modules ++ [
            { home.username = username; home.homeDirectory = homeDirectory; }
          ];
        };
    in {
      homeConfigurations = {
        # 通用入口:任何机器都用它,自动适配当前 用户/家目录/平台。
        # 需要 --impure(下面三个 builtins 会读取当前环境)。
        "generic" = mkHome {
          system        = builtins.currentSystem;
          username      = builtins.getEnv "USER";
          homeDirectory = builtins.getEnv "HOME";
        };

        # 可选:只有当某台机器需要"不一样的配置"时,才单独登记。
        # "yuu@workmac" = mkHome { system = "aarch64-darwin"; username = "yuu"; homeDirectory = "/Users/yuu"; };
      };

      # 项目级开发环境模板:`nix flake init -t ~/nixstation#<lang>` 起 devShell + direnv(.envrc)
      # 来源 modules/dev-envs/templates/;direnv/nix-direnv 已在 home/shell.nix 启用。
      templates = {
        python = { path = ./modules/dev-envs/templates/python; description = "Python dev shell (python3 + uv)"; };
        node = { path = ./modules/dev-envs/templates/node; description = "Node.js dev shell (nodejs_22 + pnpm)"; };
        rust = { path = ./modules/dev-envs/templates/rust; description = "Rust dev shell (rustc + cargo + rust-analyzer)"; };
        go = { path = ./modules/dev-envs/templates/go; description = "Go dev shell (go + gopls)"; };
        generic = { path = ./modules/dev-envs/templates/generic; description = "Generic dev shell (add tools to buildInputs)"; };
      };
    };
}

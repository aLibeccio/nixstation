# Go 项目开发环境模板(go + gopls)
#
# 用法:
#   nix flake init -t ~/nix-config#go   # 在项目目录里生成本 flake.nix + .envrc
#   direnv allow                        # 让 direnv 自动加载下面的 devShell
# 之后进入目录就自动有 go/gopls/gotools;手动进入可用 `nix develop`。
{
  description = "Go dev shell (go + gopls)";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
      in {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            go
            gopls # language server
            gotools # goimports 等
          ];

          shellHook = ''
            echo "Go dev shell — $(go version | cut -d' ' -f3)"
          '';
        };
      });
}

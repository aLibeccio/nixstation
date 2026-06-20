# Node.js 项目开发环境模板(nodejs_22 + pnpm/npm)
#
# 用法:
#   nix flake init -t ~/nix-config#node   # 在项目目录里生成本 flake.nix + .envrc
#   direnv allow                          # 让 direnv 自动加载下面的 devShell
# 之后进入目录就自动有 node/npm/pnpm;手动进入可用 `nix develop`。
{
  description = "Node.js dev shell (nodejs_22 + pnpm)";

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
            nodejs_22 # 自带 npm
            pnpm # 想用 yarn 就把这行换成 yarn
          ];

          shellHook = ''
            echo "Node dev shell — node $(node --version), pnpm $(pnpm --version)"
          '';
        };
      });
}

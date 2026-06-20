# Rust 项目开发环境模板(nixpkgs 的 rustc/cargo + rust-analyzer)
#
# 用法:
#   nix flake init -t ~/nixstation#rust   # 在项目目录里生成本 flake.nix + .envrc
#   direnv allow                          # 让 direnv 自动加载下面的 devShell
# 之后进入目录就自动有 rustc/cargo/clippy/rust-analyzer;手动进入可用 `nix develop`。
#
# 想要固定/多版本工具链(stable/nightly + 组件),把 nixpkgs 的 rustc/cargo 换成
# oxalica 的 rust-overlay(rust-bin)即可;简单起见这里直接用 nixpkgs。
{
  description = "Rust dev shell (rustc + cargo + rust-analyzer)";

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
            rustc
            cargo
            clippy
            rustfmt
            rust-analyzer
          ];

          # 让 rust-analyzer / IDE 能找到标准库源码。
          shellHook = ''
            export RUST_SRC_PATH="${pkgs.rustPlatform.rustLibSrc}"
            echo "Rust dev shell — $(rustc --version)"
          '';
        };
      });
}

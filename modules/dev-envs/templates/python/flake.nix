# Python 项目开发环境模板(用 uv 管依赖)
#
# 用法:
#   nix flake init -t ~/nix-config#python   # 在项目目录里生成本 flake.nix + .envrc
#   direnv allow                            # 让 direnv 自动加载下面的 devShell
# 之后进入目录就自动有 python3 + uv;手动进入可用 `nix develop`。
#
# 依赖管理交给 uv:
#   uv init           # 首次,生成 pyproject.toml
#   uv add <pkg>      # 加依赖
#   uv run <cmd>      # 在 .venv 里跑
{
  description = "Python dev shell (uv-managed)";

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
            python3
            uv
          ];

          # uv 默认会自己下载/管理 Python;这里让它用 nixpkgs 的 python3,
          # 避免在 NixOS 上跑预编译二进制出问题。
          shellHook = ''
            export UV_PYTHON="${pkgs.python3}/bin/python3"
            export UV_PYTHON_DOWNLOADS=never
            echo "Python dev shell — $(python3 --version), uv $(uv --version | cut -d' ' -f2)"
          '';
        };
      });
}

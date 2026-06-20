# 通用空壳开发环境模板(自己往 buildInputs 加工具)
#
# 用法:
#   nix flake init -t ~/nix-config#generic   # 在项目目录里生成本 flake.nix + .envrc
#   direnv allow                             # 让 direnv 自动加载下面的 devShell
# 之后进入目录就自动进 shell;手动进入可用 `nix develop`。
#
# 这是个空壳:把你项目要的工具加到下面 buildInputs 里即可,例如:
#   buildInputs = with pkgs; [ jq ripgrep just sqlite ];
# 包名去 https://search.nixos.org/packages 查。
{
  description = "Generic dev shell — add your own tools to buildInputs";

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
          # ↓↓↓ 在这里加你需要的包 ↓↓↓
          buildInputs = with pkgs; [
            # jq
            # ripgrep
            # just
          ];

          shellHook = ''
            echo "Generic dev shell ready — edit buildInputs in flake.nix to add tools."
          '';
        };
      });
}

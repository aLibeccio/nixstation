# dev-envs — 项目级 Nix 开发环境模板

一组 `nix flake` 模板,让你在**任意项目目录**里一条命令起一个隔离的 devShell,并靠 direnv 进目录自动加载(本仓库 `home/shell.nix` 里已启用 direnv + nix-direnv,无需额外配置)。

> 注:这些是 flake 的 `templates` 输出,**不是** home-manager 模块,所以**不进** `lib/default.nix` 的模块列表。要让 `nix flake init -t .#<lang>` 可用,只需在仓库根 `flake.nix` 加 `templates = { ... }` 输出(片段见下)。

## 用法

在你的项目目录里:

```sh
nix flake init -t ~/nix-config#python   # 生成 flake.nix + .envrc(语言换成下表任意一个)
direnv allow                            # 授权后,以后进出目录自动加载/卸载 devShell
```

不想用 direnv 也行,手动进 shell:`nix develop`。

## 可用模板

| 语言 | `init -t ~/nix-config#…` | devShell 内容 |
|---|---|---|
| Python | `python` | `python3` + `uv`(用 uv 管依赖)|
| Node.js | `node` | `nodejs_22` + `pnpm`(自带 npm)|
| Rust | `rust` | `rustc` `cargo` `clippy` `rustfmt` `rust-analyzer` |
| Go | `go` | `go` `gopls` `gotools` |
| 通用 | `generic` | 空壳,自己往 `buildInputs` 加工具 |

## 每个模板包含

- `flake.nix` —— `nixpkgs-unstable` + `flake-utils`,输出 `devShells.default = pkgs.mkShell { buildInputs = [...]; shellHook = ''...''; }`,可直接 `nix develop` 跑通。
- `.envrc` —— 一行 `use flake`,给 direnv 用。

## 加工具 / 改版本

直接编辑生成出来的 `flake.nix` 里的 `buildInputs`(包名去 https://search.nixos.org/packages 查),保存后 direnv 会自动重载。

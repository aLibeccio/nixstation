# dev-envs

Project-local Nix flake templates for isolated dev shells. They are flake `templates`, not home-manager modules, so they are exported from the root `flake.nix` and are not listed in `lib/default.nix`.

## Usage

```sh
nix flake init -t ~/nixstation#python
direnv allow
```

Use `nix develop` instead of direnv when you want to enter the shell manually.

## Templates

| Template | Tools |
|---|---|
| `python` | `python3`, `uv` |
| `node` | `nodejs_22`, `pnpm` |
| `rust` | `rustc`, `cargo`, `clippy`, `rustfmt`, `rust-analyzer` |
| `go` | `go`, `gopls`, `gotools` |
| `generic` | empty shell for project-specific tools |

Each template writes a `flake.nix` and `.envrc`. Add packages to `buildInputs` and let direnv reload the shell.

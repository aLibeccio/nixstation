# nixstation

Declarative workstation setup with Nix flakes and home-manager. It installs a modern CLI toolchain, shell/editor settings, AI-agent harness services, and reusable per-project devShell templates.

## Quick Start

| Task | Command |
|---|---|
| Apply config | `hms` |
| Apply without alias | `home-manager switch --flake ~/nixstation#generic --impure` |
| Update inputs | `cd ~/nixstation && nix flake update && hms` |
| Pull on another machine | `git -C ~/nixstation pull && hms` |
| Bootstrap new machine | `curl -fsSL https://raw.githubusercontent.com/aLibeccio/nixstation/main/bootstrap.sh \| sh` |

New `.nix` files must be tracked by Git before `hms`; flakes only see tracked files.

## Modules

- `home/`: packages, shell integration, and program settings.
- `modules/homebrew/`: GUI casks and fonts; runtime CLIs stay in Nix.
- `modules/agent-harness/`: agentmemory service plus MCP registration.
- `modules/agent-tooling/`: Codex/Claude CLI preference and Codex shell PATH policy.
- `modules/evidence-discipline/`: investigation discipline snippets and Claude stop hook.
- `modules/agentmemory-prefer/`: local embedding settings and agentmemory skills.
- `modules/memory-sync/`: optional rclone bisync shared memory store.
- `modules/dev-envs/`: flake templates for project-local dev shells.

## CLI Tool Catalog

This catalog is the human-facing index of supported CLI functionality. The source of truth is still the Nix config in `home/packages.nix`, `home/programs.nix`, and `home/shell.nix`.

### Core Data And Files

| Tool | What It Does | Common Use |
|---|---|---|
| `curl` | HTTP/file transfer | `curl -fsSL URL` |
| `xh` | HTTP client with readable output | `xh GET example.com` |
| `jq` | JSON query/transform | `jq '.items[].name' file.json` |
| `yq` | YAML query/transform | `yq '.services' compose.yaml` |
| `dasel` | Query JSON/YAML/TOML/XML/CSV | `dasel -f config.toml '.server.port'` |
| `gron` | Flatten JSON for grep | `gron file.json` |
| `duckdb` | SQL over local data files | `duckdb -c "SELECT * FROM 'data.csv' LIMIT 5"` |
| `psql` | PostgreSQL client tools | `psql -h host -U user db` |
| `mlr` | CSV/TSV/JSON processing | `mlr --csv cut -f name,age data.csv` |
| `shfmt` | Shell formatter | `shfmt -w script.sh` |
| `eza` | Modern `ls` | `eza -la --git --icons` |
| `bat` | Syntax-highlighted file viewer | `bat file.rs` |
| `rg` | Fast text search | `rg "TODO" -t py` |
| `fd` | Friendly file search | `fd '\.nix$'` |
| `sd` | Simple find/replace | `sd 'old' 'new' file.txt` |
| `dust` | Disk usage explorer | `dust -d 2` |
| `tailspin` | Log highlighter | `tailspin app.log` |
| `hexyl` | Hex viewer | `hexyl file.bin` |
| `doggo` | DNS lookup client | `doggo example.com` |
| `trippy` | Network path diagnosis | `trip example.com` |
| `bandwhich` | Per-process bandwidth view | `sudo bandwhich` |
| `glow` | Terminal Markdown renderer | `glow README.md` |
| `jless` | TUI JSON/YAML viewer | `jless data.json` |

### Nix And System

| Tool | What It Does | Common Use |
|---|---|---|
| `hms` | Local alias for home-manager switch | `hms` |
| `nh` | Ergonomic Nix workflow helper | `nh home switch .#generic` |
| `nom` | Nix build progress monitor | `nix build .#pkg --log-format internal-json \| nom --json` |
| `nixd` | Nix language server | Used by editors |
| `nixfmt` | Nix formatter | `nixfmt file.nix` |
| `statix` | Nix linter | `statix check` |
| `deadnix` | Find unused Nix code | `deadnix .` |
| `nix-tree` | Explore Nix closures | `nix-tree result` |
| `btop` | System monitor | `btop` |
| `procs` | Modern process viewer | `procs --tree` |
| `fastfetch` | System summary | `fastfetch` |
| `hyperfine` | Command benchmarking | `hyperfine 'rg foo' 'grep -r foo .'` |
| `oha` | HTTP load testing | `oha -n 1000 http://localhost:8080` |

### Development And Git

| Tool | What It Does | Common Use |
|---|---|---|
| `git` | Version control, declaratively configured | `git st` |
| `gh` | GitHub CLI and git credential helper | `gh auth status` |
| `lazygit` | Terminal Git UI | `lazygit` |
| `delta` | Syntax-highlighted git diffs | Used by git pager |
| `difft` | Syntax-aware structural diff | `difft old new` |
| `git-lfs` | Git large-file storage | `git lfs track "*.psd"` |
| `gitleaks` | Secret scanner | `gitleaks detect` |
| `sops` | Encrypted secrets files | `sops secrets.yaml` |
| `age` | File encryption | `age -r <pubkey> -o file.age file` |
| `watchexec` | Run commands on file changes | `watchexec -e rs cargo test` |
| `usage` | CLI usage/spec tooling | `usage --help` |
| `shellcheck` | Shell static analysis | `shellcheck script.sh` |
| `yamlfmt` | YAML formatter | `yamlfmt .` |
| `pre-commit` | Git hook runner | `pre-commit run --all-files` |
| `just` | Command runner | `just --list` |
| `mise` | Runtime/tool version manager | `mise list` |
| `uv` | Fast Python package/tool manager | `uv tool run ruff --help` |
| `node`/`npm`/`npx` | Node.js LTS toolchain | `node --version` |
| `go` | Go toolchain | `go test ./...` |
| `golangci-lint` | Go lint runner | `golangci-lint run` |
| `python3` | Python interpreter | `python3 --version` |
| `tokei` | Code line statistics | `tokei` |
| `grex` | Generate regex from examples | `grex 1.2.3 4.5.6` |

### Infrastructure And Cloud

| Tool | What It Does | Common Use |
|---|---|---|
| `kubectl` | Kubernetes CLI | `kubectl get pods` |
| `k9s` | Kubernetes terminal UI | `k9s` |
| `kubectx` | Switch Kubernetes contexts | `kubectx` |
| `kubens` | Switch Kubernetes namespaces | `kubens` |
| `helm` | Kubernetes package manager | `helm list` |
| `minikube` | Local Kubernetes cluster | `minikube start` |
| `stern` | Multi-pod log tailing | `stern app` |
| `dive` | Inspect container image layers | `dive image:tag` |
| `lazydocker` | Container terminal UI | `lazydocker` |
| `aws` | AWS CLI | `aws s3 ls` |
| `rclone` | Cloud storage sync | `rclone copy ./ remote:path` |

### Files, Media, And Documents

| Tool | What It Does | Common Use |
|---|---|---|
| `yt-dlp` | Video/audio download | `yt-dlp URL` |
| `ffmpeg` | Audio/video conversion | `ffmpeg -i in.mov out.mp4` |
| `unar` | Archive extraction | `unar archive.7z` |
| `ouch` | Unified archive tool | `ouch decompress archive.tar.gz` |
| `typst` | Document compiler | `typst compile doc.typ` |

### Shell, Navigation, And Editors

| Tool | What It Does | Common Use |
|---|---|---|
| `fzf` | Fuzzy finder | `Ctrl-T`, `Alt-C` |
| `zoxide` | Smarter `cd` | `z project` |
| `atuin` | Searchable shell history | `Ctrl-R` |
| `starship` | Shell prompt | Loaded by zsh |
| `direnv` | Auto-load project shells | `direnv allow` |
| `navi` | Interactive cheatsheets | `navi` |
| `rtk` | Token-saving CLI proxy | `rtk --help` |
| `zellij` | Terminal multiplexer | `zellij` |
| `yazi` | Terminal file manager | `yazi` |
| `tldr` | Short command examples | `tldr tar` |
| `carapace` | Cross-shell completions | Loaded by zsh |
| `fzf-tab` | Fuzzy completion menu | Press `Tab` |
| `hx` | Helix editor | `hx file.nix` |

### Platform-Specific Containers

| Platform | Tools | Common Use |
|---|---|---|
| macOS | `colima`, `docker` | `colima start`, then `docker ps` |
| Linux | `podman`, `buildah`, `skopeo` | `podman ps`, `buildah bud`, `skopeo inspect` |

## Agent CLI Tooling

Codex and Claude Code should prefer the Nix/home-manager CLI toolchain for repeatable command behavior. The managed PATH puts `~/.nix-profile/bin` and `/nix/var/nix/profiles/default/bin` before npm, local, Homebrew, and system paths.

Use enhanced tools for interactive inspection and coding workflows. Keep POSIX basics such as `cat`, `ls`, `find`, `sed`, and `awk` in scripts or parsed pipelines when stable output matters. If a tool is uncertain on a machine, run `command -v <tool>` and prefer the Nix profile path.

## AI Agent Harness

- `agentmemory`: shared long-term memory MCP server, default REST port `3111`.
- Viewer and memory tools are local-only operational aids; do not commit memory data or credentials.

## Dev Shell Templates

Create a project-local shell:

```sh
nix flake init -t ~/nixstation#python
direnv allow
```

Templates: `python`, `node`, `rust`, `go`, and `generic`. See `modules/dev-envs/README.md`.

## Maintenance

- Change configuration in this repo, then run `hms`.
- Keep secrets and machine-local data outside Git.
- Keep comments short and about behavior, not local rationale or topology.

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
- `modules/agent-harness/`: agentmemory and headroom services plus MCP registration.
- `modules/agent-tooling/`: Codex/Claude CLI tool preference and Codex shell PATH policy.
- `modules/evidence-discipline/`: investigation discipline snippets and Claude stop hook.
- `modules/agentmemory-prefer/`: local embedding settings and agentmemory skills.
- `modules/memory-sync/`: optional rclone bisync for the shared memory store.
- `modules/dev-envs/`: flake templates for project-local dev shells.

## Agent CLI Tooling

Codex and Claude Code should prefer the Nix/home-manager CLI toolchain for repeatable command behavior. The managed PATH puts `~/.nix-profile/bin` and `/nix/var/nix/profiles/default/bin` first for tools such as `rg`, `fd`, `jq`, `yq`, `bat`, `eza`, `delta`, `fzf`, `zoxide`, `kubectl`, `aws`, `go`, `mvn`, and `gradle`.

Do not replace POSIX basics in scripts or parsed pipelines. Use enhanced tools for interactive inspection, but keep `cat`, `ls`, `find`, `sed`, and `awk` where stable output matters.

## AI Agent Harness

- `agentmemory`: shared long-term memory and MCP server, default REST port `3111`.
- `headroom`: context-compression proxy, default port `8787`.
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
- Use short comments that explain what a rule does; avoid private rationale or local topology.

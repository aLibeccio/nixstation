<!-- agent-tooling:v1 -->

## Agent CLI Tooling

Prefer Nix/home-manager managed CLI tools when running commands.

- Prefer `~/.nix-profile/bin` and `/nix/var/nix/profiles/default/bin`.
- Use modern tools when helpful: `rg`, `fd`, `jq`, `yq`, `bat`, `eza`, `delta`, `fzf`, `zoxide`, `dust`, `sd`, `difft`, `kubectl`, `aws`, `node`, `go`, `python3`, `uv`, `just`.
- Do not alias POSIX basics in scripts or parsed pipelines. Keep `cat`, `ls`, `find`, `sed`, and `awk` when stable output matters.
- If unsure, run `command -v <tool>` and prefer the Nix profile path.
<!-- end agent-tooling:v1 -->

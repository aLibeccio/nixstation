{
  config,
  lib,
  pkgs,
  ...
}:

let
  awk = "${pkgs.gawk}/bin/awk";
  home = config.home.homeDirectory;
  preferredPath = lib.concatStringsSep ":" [
    "${home}/.nix-profile/bin"
    "/nix/var/nix/profiles/default/bin"
    "${home}/.npm-global/bin"
    "${home}/.local/bin"
    "/opt/homebrew/bin"
    "/opt/homebrew/sbin"
    "/usr/local/bin"
    "/usr/bin"
    "/bin"
    "/usr/sbin"
    "/sbin"
  ];
in
{
  home.activation = {
    agentToolingCodexPath = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      CONFIG="$HOME/.codex/config.toml"
      BEGIN="# --- nixstation agent tool PATH ---"
      END="# --- end nixstation agent tool PATH ---"
      PREFERRED_PATH=${lib.escapeShellArg preferredPath}

      if [ ! -f "$CONFIG" ]; then
        echo "[agent-tooling] $CONFIG missing, skip Codex PATH policy"
      else
        TMP=$(mktemp "''${CONFIG}.XXXXXX")
        ${awk} -v begin="$BEGIN" -v end="$END" '
          $0 == begin { skip = 1; next }
          $0 == end { skip = 0; next }
          !skip { print }
        ' "$CONFIG" > "$TMP"

        if grep -Eq "^[[:space:]]*\\[shell_environment_policy\\][[:space:]]*$" "$TMP"; then
          rm -f "$TMP"
          echo "[agent-tooling] custom Codex shell policy found, left config unchanged"
        else
          {
            printf "\n%s\n" "$BEGIN"
            printf "[shell_environment_policy]\n"
            printf "set = { PATH = \"%s\" }\n" "$PREFERRED_PATH"
            printf "%s\n" "$END"
          } >> "$TMP"
          mv "$TMP" "$CONFIG"
          echo "[agent-tooling] updated Codex shell PATH policy"
        fi
      fi
    '';

    agentToolingInstructions = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      MARK="<!-- agent-tooling:v1 -->"
      END="<!-- end agent-tooling:v1 -->"
      SNIPPET=${./assets/AGENTS.snippet.md}
      for AG in "$HOME/.codex/AGENTS.md" "$HOME/.claude/CLAUDE.md"; do
        if [ ! -f "$AG" ]; then
          echo "[agent-tooling] $AG missing, skip instructions"
        elif grep -qF "$MARK" "$AG" 2>/dev/null; then
          TMP=$(mktemp "''${AG}.XXXXXX")
          ${awk} -v mark="$MARK" -v end="$END" -v snippet="$SNIPPET" '
            function emit_snippet() {
              while ((getline line < snippet) > 0) print line
              close(snippet)
            }
            $0 == mark {
              emit_snippet()
              skip = 1
              next
            }
            skip && $0 == end {
              skip = 0
              next
            }
            skip && /^<!-- [^>]+ -->$/ {
              skip = 0
              print
              next
            }
            skip {
              next
            }
            { print }
          ' "$AG" > "$TMP"
          mv "$TMP" "$AG"
          echo "[agent-tooling] updated $(basename "$AG") instructions"
        else
          { printf "\n"; cat "$SNIPPET"; } >> "$AG"
          echo "[agent-tooling] appended instructions to $AG"
        fi
      done
    '';
  };
}

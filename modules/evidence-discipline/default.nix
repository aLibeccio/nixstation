{ config, lib, pkgs, ... }:
# evidence-discipline: require evidence for live/debugging claims.
# Installs a Claude skill, a Codex snippet, and a Claude Stop hook.
# Set EVIDENCE_DISCIPLINE_OFF=1 to bypass the hook.
let
  py = "${pkgs.python3}/bin/python3";
  jq = "${pkgs.jq}/bin/jq";
in
{
  # Managed Claude skill and hook.
  home.file.".claude/skills/evidence-discipline/SKILL.md".source = ./assets/SKILL.md;
  home.file.".claude/hooks/evidence-stop-verify.py".source = ./assets/stop-verify.py;
  # Shared verdict core, imported by the Claude entrypoint (Codex side imports its own copy).
  home.file.".claude/hooks/evidence_core.py".source = ./assets/evidence_core.py;

  # Codex side: same shared core + a Codex Stop entrypoint (last_assistant_message
  # + grep-transcript evidence, fail-open). Registered into config.toml below.
  home.file.".codex/hooks/evidence_core.py".source = ./assets/evidence_core.py;
  home.file.".codex/hooks/codex-stop.py".source = ./assets/codex-stop.py;

  # Codex implementer watchdog wrapper (hard cap + idle kill); also sets
  # EVIDENCE_NO_BLOCK=1 + --dangerously-bypass-hook-trust for the evidence hook.
  # force: it was previously an unmanaged plain file in ~/.claude.
  home.file.".claude/codex-guarded.sh" = {
    source = ./assets/codex-guarded.sh;
    executable = true;
    force = true;
  };

  home.activation = {
    # Register the Claude Stop + SubagentStop hook (same script covers both).
    evidenceClaudeHook = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      CJ="$HOME/.claude/settings.json"
      HOOK="$HOME/.claude/hooks/evidence-stop-verify.py"
      CMD="${py} $HOOK"
      if [ ! -f "$CJ" ]; then
        echo "[evidence-discipline] $CJ 不存在,跳过 Stop/SubagentStop hook 注入"
      else
        NEW=$(${jq} --arg cmd "$CMD" '
          .hooks = (.hooks // {})
          | .hooks.Stop = (
              ((.hooks.Stop // []) | map(select(
                ([ (.hooks // [])[]?.command ] | map(select(. != null)) | any(test("evidence-stop-verify"))) | not
              )))
              + [ { "hooks": [ { "type": "command", "command": $cmd } ] } ]
            )
          | .hooks.SubagentStop = (
              ((.hooks.SubagentStop // []) | map(select(
                ([ (.hooks // [])[]?.command ] | map(select(. != null)) | any(test("evidence-stop-verify"))) | not
              )))
              + [ { "hooks": [ { "type": "command", "command": $cmd } ] } ]
            )
        ' "$CJ" 2>/dev/null) || NEW=""
        if [ -z "$NEW" ]; then
          echo "[evidence-discipline] jq 处理失败,保持 settings.json 原样不变"
        elif [ "$NEW" = "$(cat "$CJ")" ]; then
          echo "[evidence-discipline] Stop hook 已是最新,no-op"
        else
          TMP=$(mktemp "''${CJ}.XXXXXX")
          if printf '%s\n' "$NEW" > "$TMP" && [ -s "$TMP" ]; then
            mv "$TMP" "$CJ"
            echo "[evidence-discipline] 已注入/更新 Claude Stop hook"
          else
            rm -f "$TMP"
            echo "[evidence-discipline] 写 settings.json 失败,原文件不变"
          fi
        fi
      fi
    '';

    # Append the Codex evidence snippet once.
    evidenceCodexAgents = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      AG="$HOME/.codex/AGENTS.md"
      MARK="evidence-discipline:v1"
      if [ ! -f "$AG" ]; then
        echo "[evidence-discipline] $AG 不存在,跳过 Codex AGENTS.md 切片"
      elif grep -qF "$MARK" "$AG" 2>/dev/null; then
        echo "[evidence-discipline] AGENTS.md 切片已存在,no-op"
      else
        if { printf '\n'; cat ${./assets/AGENTS.snippet.md}; } >> "$AG"; then
          echo "[evidence-discipline] 已追加 Codex AGENTS.md 切片"
        else
          echo "[evidence-discipline] 写 AGENTS.md 失败"
        fi
      fi
    '';

    # Register the Codex Stop hook in config.toml (fenced block; awk self-heal:
    # delete old block then re-append → idempotent and updates on python-path bumps).
    evidenceCodexHook = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      CT="$HOME/.codex/config.toml"
      HOOK="$HOME/.codex/hooks/codex-stop.py"
      CMD="${py} $HOOK"
      BEGIN_MARK="# --- nixstation evidence-discipline hooks ---"
      END_MARK="# --- end nixstation evidence-discipline hooks ---"
      if [ ! -f "$CT" ]; then
        echo "[evidence-discipline] $CT 不存在,跳过 Codex Stop hook 注入"
      else
        TMP=$(mktemp "''${CT}.XXXXXX")
        ${pkgs.gawk}/bin/awk -v b="$BEGIN_MARK" -v e="$END_MARK" '
          $0==b {skip=1}
          skip==0 {print}
          $0==e {skip=0}
        ' "$CT" > "$TMP"
        {
          printf '\n%s\n' "$BEGIN_MARK"
          printf '[[hooks.Stop]]\n'
          printf '[[hooks.Stop.hooks]]\n'
          printf 'type = "command"\n'
          printf 'command = "%s"\n' "$CMD"
          printf '%s\n' "$END_MARK"
        } >> "$TMP"
        if [ -s "$TMP" ] && ${py} -c "import tomllib,sys; tomllib.load(open(sys.argv[1],'rb'))" "$TMP" 2>/dev/null; then
          mv "$TMP" "$CT"
          echo "[evidence-discipline] 已注入/更新 Codex Stop hook"
        else
          rm -f "$TMP"
          echo "[evidence-discipline] Codex hook 注入后 TOML 非法或为空,保持原文件不变"
        fi
      fi
    '';
  };
}

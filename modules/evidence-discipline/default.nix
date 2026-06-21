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

  home.activation = {
    # Register the Claude Stop hook.
    evidenceClaudeHook = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      CJ="$HOME/.claude/settings.json"
      HOOK="$HOME/.claude/hooks/evidence-stop-verify.py"
      CMD="${py} $HOOK"
      if [ ! -f "$CJ" ]; then
        echo "[evidence-discipline] $CJ 不存在,跳过 Stop hook 注入"
      else
        NEW=$(${jq} --arg cmd "$CMD" '
          .hooks = (.hooks // {})
          | .hooks.Stop = (
              ((.hooks.Stop // []) | map(select(
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
  };
}

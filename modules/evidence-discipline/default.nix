{ config, lib, pkgs, ... }:
# evidence-discipline —— 给 Claude Code + Codex 加一层「调查取证 / 反幻觉」约束。
# 背景:排查 bug / 查事实(尤其 EKS Java 服务)时,常见失效是"没跑 kubectl 就断言 live 状态、
# 没复现就下根因、没验证就说修好了"。CLAUDE.md/AGENTS.md 其实已写过 kubectl-first,但纯指令在
# 压力下会漏。所以这里:① 装一个 skill(详细协议,模型按需加载);② Codex 侧追加 AGENTS.md 切片;
# ③ 装一个 Claude Code Stop hook,收尾时对照 transcript 检查"承重断言"是否有工具证据,没有就拦下。
#
# 落地沿用 agent-config 的哲学:只注入我们在意的切片、幂等、不接管整文件;文件不存在则跳过。
# 逃生阀:EVIDENCE_DISCIPLINE_OFF=1 claude → hook 完全不拦(hook 内部还会对任何异常 fail-open)。
let
  py = "${pkgs.python3}/bin/python3";
  jq = "${pkgs.jq}/bin/jq";
in
{
  # ── 受管文件:skill 与 hook 脚本由 Nix 提供(可复现、git 同步)──
  # skill:Claude Code 个人技能,放在 ~/.claude/skills/<name>/SKILL.md(与现有 symlink 技能并存)。
  home.file.".claude/skills/evidence-discipline/SKILL.md".source = ./assets/SKILL.md;
  # Stop hook 脚本:settings.json 里用绝对路径 + Nix python3 显式调用,故不需要可执行位。
  home.file.".claude/hooks/evidence-stop-verify.py".source = ./assets/stop-verify.py;

  home.activation = {
    # ── ① 幂等注册 Stop hook 到 ~/.claude/settings.json ──
    # 只动 .hooks.Stop,其余字节原样保留;按 value 幂等:先删掉旧的 evidence 入口再补当前的,
    # 故 python3 版本变更后下次 hms 会自愈成新 store 路径。文件不存在则跳过(不造半成品)。
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

    # ── ② 幂等追加 evidence 切片到 Codex 的 ~/.codex/AGENTS.md ──
    # 用首行 marker 守卫,已存在则 no-op;只 append、不改原有内容。文件不存在则跳过。
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

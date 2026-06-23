#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
evidence-discipline Stop hook (Codex CLI)
=========================================
Codex 收尾(Stop)时,检查 last_assistant_message 里「根因 / live 状态 / 已修复」三类
承重断言是否有本轮工具调用支撑;没支撑、又没自标 [假设]/[推断]/[未知] 的就 block。

与 Claude 侧共享 evidence_core.py(判定逻辑一份 source-of-truth、不漂移)。差异只在 I/O:
  * 承重断言:直接用 stdin 的 last_assistant_message(Codex 给的完整最终回答)。
  * 证据采集:读 transcript_path 原文 grep 证据命令正则(Codex transcript 把执行过的
    命令以文本记录——shell 工具 exec_command,命令串就在文件里,grep 命中即「跑过」)。
  * fail-open:transcript 读不到 / 格式不认 / 任何异常 → 放行。这是有意取舍——Codex
    升级把 transcript 改了,harness 静默回到现状,不误拦、不损坏数据,可察觉再修。

近似说明:证据 grep 覆盖整个 session transcript(非严格「本轮」),偏宽松——可能漏拦
(本轮没跑但本 session 早先跑过),不会误拦,符合 fail-open 轻量定位。

阻断协议:stdout 打印 {"decision":"block","reason":...}(Codex 会喂 reason 让 agent
自动续跑一轮补证据);stop_hook_active 防止续跑死循环。

环境开关:
  * EVIDENCE_DISCIPLINE_OFF=1 → 完全旁路。
  * EVIDENCE_NO_BLOCK=1     → warn-only:提醒打到 stderr,但不 block。codex-guarded.sh
                              跑 implementer 时设此,避免 block 续跑撞 wrapper 的 hard cap。
  * EVIDENCE_DEBUG=1        → dump payload 到 $TMPDIR/codex-evidence-debug.log。
"""
import sys
import os
import json

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import evidence_core as core


def _pass():
    sys.exit(0)


def _block(reason):
    print(json.dumps({"decision": "block", "reason": reason}, ensure_ascii=False))
    sys.exit(0)


def _warn(reason):
    # warn-only:不阻断,只把提醒写 stderr(供日志/人看),exit 0 放行。
    sys.stderr.write("[evidence-discipline][warn] " + reason.splitlines()[0] + "\n")
    sys.exit(0)


def _collect_evidence(path):
    """读 transcript 原文,grep 证据命令正则。读不到 → None(fail-open 信号)。"""
    try:
        with open(path, "r", encoding="utf-8", errors="ignore") as f:
            txt = f.read()
    except Exception:
        return None
    ev = {"live": False, "verify": False, "read": False, "grep": False}
    if core.RX_LIVE_CMD.search(txt):
        ev["live"] = True
    if core.RX_VERIFY_CMD.search(txt):
        ev["verify"] = True
    if core.RX_GREP_CMD.search(txt):
        ev["grep"] = True
    return ev


def main():
    if os.environ.get("EVIDENCE_DISCIPLINE_OFF"):
        _pass()
    raw = sys.stdin.read()
    try:
        data = json.loads(raw) if raw.strip() else {}
    except Exception:
        _pass()
        return

    if os.environ.get("EVIDENCE_DEBUG"):
        try:
            d = os.environ.get("TMPDIR", "/tmp").rstrip("/")
            with open(d + "/codex-evidence-debug.log", "a", encoding="utf-8") as f:
                f.write(json.dumps(data, ensure_ascii=False) + "\n")
        except Exception:
            pass

    if data.get("stop_hook_active"):
        _pass()                       # 防循环:block 后的续跑不再拦

    final_text = data.get("last_assistant_message") or ""
    if not final_text.strip():
        _pass()

    # 上下文闸:非运维/排查语境 → 不启用(Codex 侧只有最终回答可凭,无 user 消息)。
    if not core.RX_OPS.search(final_text):
        _pass()

    # 没有承重断言就不必读 transcript。
    if not (core.RX_ROOTCAUSE.search(final_text)
            or core.RX_LIVE.search(final_text)
            or core.RX_FIXED.search(final_text)):
        _pass()

    # 有承重断言 → 采集证据。fail-open:读不到 transcript 就放行。
    path = data.get("transcript_path")
    ev = _collect_evidence(path) if path else None
    if ev is None:
        _pass()                       # fail-open

    problems = core.build_problems(final_text, ev)
    if not problems:
        _pass()

    reason = core.reason_text(problems)
    if os.environ.get("EVIDENCE_NO_BLOCK"):
        _warn(reason)                 # warn-only(guarded implementer 场景)
    _block(reason)


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception:
        sys.exit(0)                   # 兜底 fail-open

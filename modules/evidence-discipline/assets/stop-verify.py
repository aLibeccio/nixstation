#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
evidence-discipline Stop / SubagentStop hook (Claude Code)
=========================================================
收尾时检查最终回答里「根因 / live 状态 / 已修复」三类承重断言,是否有本轮真实工具
调用(kubectl / 日志 / ClickHouse / k8s-MCP / 验证命令 / 读文件 / grep)支撑;没支撑、
又没自标 [假设]/[推断]/[未知] 的,就 block 并要求补命令或降级标注。

覆盖范围:
  * Stop          —— 主 agent 收尾。
  * SubagentStop  —— 子 agent(Task)收尾;同一脚本,按 hook_event_name 走同一套判定。

判定逻辑在 evidence_core.py(与 Codex 侧共享,一份 source-of-truth、不漂移)。本文件
只负责 Claude 侧 I/O:解析 Claude transcript JSONL 采集证据,再调 core 判定。

保守设计(不误伤、不卡正常使用):
  * 只在运维/排查语境(core.RX_OPS 命中)启用;纯概念问答/普通聊天放行。
  * 自标 [实测]/[假设]/[推断]/[未知] 的句子放行(奖励诚实标注)。
  * 任何异常 / transcript 读不到 / stop_hook_active → 放行(fail-open,exit 0)。
  * EVIDENCE_DISCIPLINE_OFF=1 → 完全旁路。
  * EVIDENCE_DEBUG=1 → 把收到的 payload dump 到 $TMPDIR/evidence-discipline-debug.log(实测用)。

输入:stdin 的 Stop/SubagentStop hook JSON(hook_event_name / transcript_path /
      stop_hook_active 等)。
输出:放行 → exit 0 无输出;拦截 → exit 0 且 stdout 打印 {"decision":"block","reason":...}。
"""
import sys
import os
import json

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import evidence_core as core


def _pass():
    sys.exit(0)


def _block(reason):
    print(json.dumps({"decision": "block", "reason": reason, "suppressOutput": True}, ensure_ascii=False))
    sys.exit(0)


def _dbg(data):
    """实测用:EVIDENCE_DEBUG=1 时把 payload 落盘,确认 Stop/SubagentStop 真实字段。"""
    try:
        d = os.environ.get("TMPDIR", "/tmp").rstrip("/")
        with open(d + "/evidence-discipline-debug.log", "a", encoding="utf-8") as f:
            f.write(json.dumps(data, ensure_ascii=False) + "\n")
    except Exception:
        pass


def _iter_msgs(path):
    with open(path, "r", encoding="utf-8", errors="ignore") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except Exception:
                continue
            msg = obj.get("message")
            if isinstance(msg, dict) and msg.get("role") in ("user", "assistant"):
                yield msg["role"], msg


def _scan_tools(msg, ev):
    """扫一条 assistant message 的 tool_use,更新证据标志字典 ev。"""
    content = msg.get("content")
    if not isinstance(content, list):
        return
    for b in content:
        if not isinstance(b, dict) or b.get("type") != "tool_use":
            continue
        name = b.get("name") or ""
        inp = b.get("input") if isinstance(b.get("input"), dict) else {}
        if name == "Bash":
            c = str(inp.get("command") or "")
            if core.RX_LIVE_CMD.search(c):
                ev["live"] = True
            if core.RX_VERIFY_CMD.search(c):
                ev["verify"] = True
            if core.RX_GREP_CMD.search(c):
                ev["grep"] = True
        elif name == "Read":
            ev["read"] = True
        elif core.RX_MCP_OPS.search(name):
            # k8s / ClickHouse MCP 查询 = live 证据,且足以充当验证
            ev["live"] = True
            ev["verify"] = True


def main():
    if os.environ.get("EVIDENCE_DISCIPLINE_OFF"):
        _pass()          # 逃生阀:EVIDENCE_DISCIPLINE_OFF=1 → 本 hook 完全不拦
    raw = sys.stdin.read()
    try:
        data = json.loads(raw) if raw.strip() else {}
    except Exception:
        _pass()
        return

    if os.environ.get("EVIDENCE_DEBUG"):
        _dbg(data)

    # 防循环:block 后的续跑不再拦。Stop 提供 stop_hook_active;SubagentStop 无此字段
    # 则取到 None(不放行),接受子 agent 侧无此兜底——最坏多续几轮,子 agent 自有 turn 上限。
    if data.get("stop_hook_active"):
        _pass()

    # 注:不再因「这是子 agent」而豁免 —— Stop 管主、SubagentStop 管子,两者都校验。
    path = data.get("transcript_path")
    if not path:
        _pass()

    try:
        msgs = list(_iter_msgs(path))
    except Exception:
        _pass()
        return
    if not msgs:
        _pass()

    last_user = max((i for i, (r, _m) in enumerate(msgs) if r == "user"), default=-1)
    last_user_text = core.text_of(msgs[last_user][1].get("content")) if last_user >= 0 else ""
    turn = msgs[last_user + 1:] if last_user >= 0 else msgs

    ev = {"live": False, "verify": False, "read": False, "grep": False}
    last_assist = None
    for role, m in turn:
        if role == "assistant":
            last_assist = m
            _scan_tools(m, ev)
    if last_assist is None:
        _pass()

    final_text = core.text_of(last_assist.get("content"))
    if not final_text or not final_text.strip():
        _pass()

    # 上下文闸:非运维/排查语境 → 不启用(文本层 skill/AGENTS 仍在管)。
    ctx = "\n".join([final_text, last_user_text])
    if not core.RX_OPS.search(ctx):
        _pass()

    problems = core.build_problems(final_text, ev)
    if not problems:
        _pass()
    _block(core.reason_text(problems))


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception:
        sys.exit(0)   # 兜底 fail-open

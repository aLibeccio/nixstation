#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
evidence-discipline Stop hook (Claude Code)
===========================================
主 agent 收尾时,检查最终回答里关于 ① 根因 ② live 集群/运行时状态 ③「已修复/部署成功」
三类「承重断言」是否有本轮真实工具调用支撑(kubectl / 日志 / ClickHouse / k8s-MCP / 验证命令)。
没支撑、又没自标 [假设]/[推断]/[未知] 的,就 block 并要求补命令或降级标注。

保守设计(不误伤、不死循环、不卡正常使用):
  * 只在「运维/排查上下文」(RX_OPS 命中)才启用;纯概念问答/普通聊天一律放行。
  * 自标 [假设]/[推断]/[未知]/[实测] 的句子放行(奖励诚实标注)。
  * 证据来源认 Bash(kubectl/grep/SELECT…)、k8s/ClickHouse MCP 工具、以及 Read(读真实文件)。
  * 任何异常 / transcript 读不到 / 子 agent 收尾 / stop_hook_active → 放行(fail-open,exit 0)。

输入:stdin 的 Stop hook JSON(transcript_path / stop_hook_active / agent_id 等)。
输出:放行 → exit 0 无输出;拦截 → exit 0 且 stdout 打印 {"decision":"block","reason":...}。
"""
import sys
import os
import json
import re

# —— 承重断言(最终回答里出现 = 可能需要证据)——
RX_ROOTCAUSE = re.compile(r"根因|根本原因|问题出在|原因是|就是因为|root cause", re.I)
RX_FIXED = re.compile(r"已修复|修复完成|已经修好|已解决|问题解决|已部署|已上线|已生效|应该(就)?好了|fixed|deployed|resolved|should be working", re.I)
RX_LIVE = re.compile(
    r"(pod|节点|实例|副本|容器).{0,18}(在|正在|已经|目前|当前|现在).{0,12}(运行|Running|Ready|重启|崩溃|挂|OOM|CrashLoop)"
    r"|当前.{0,8}(状态|副本数|连接数|实例数)"
    r"|(pod|容器).{0,16}(Running|Ready|OOMKilled|CrashLoopBackOff)",
    re.I,
)

# —— 上下文闸:只在运维/排查语境启用 ——
RX_OPS = re.compile(r"kubectl|k8s|kubernetes|eks|\bpod\b|集群|节点|部署|上线|线上|生产|rollout|clickhouse|日志|故障|排查|incident|crashloop|oom|nacos|apollo", re.I)

# —— 证据探测:Bash 命令 ——
RX_LIVE_CMD = re.compile(r"\bkubectl\b|\baws\s|clickhouse|clickhouse-client|\bpsql\b|\bmysql\b|\bjournalctl\b| logs?\b|describe|\bSELECT\s", re.I)
RX_VERIFY_CMD = re.compile(r"kubectl\s+rollout|kubectl\s+get\s+pods?|kubectl\s+describe|kubectl\s+top|--previous|\bcurl\b|重跑|重新跑|re-?run", re.I)
RX_GREP_CMD = re.compile(r"\bgrep\b|\brg\b|\bawk\b|\bsed\b", re.I)
# —— 证据探测:MCP 工具名(用户已注册只读 kubernetes MCP)——
RX_MCP_OPS = re.compile(r"kubernetes|kube|clickhouse", re.I)

RX_LABELED = re.compile(r"\[\s*(实测|推断|假设|未知)")


def _pass():
    sys.exit(0)


def _block(reason: str):
    print(json.dumps({"decision": "block", "reason": reason, "suppressOutput": True}, ensure_ascii=False))
    sys.exit(0)


def _text(content):
    if isinstance(content, str):
        return content
    out = []
    if isinstance(content, list):
        for b in content:
            if isinstance(b, dict) and b.get("type") == "text":
                out.append(b.get("text") or "")
            elif isinstance(b, str):
                out.append(b)
    return "\n".join(out)


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
            if RX_LIVE_CMD.search(c):
                ev["live"] = True
            if RX_VERIFY_CMD.search(c):
                ev["verify"] = True
            if RX_GREP_CMD.search(c):
                ev["grep"] = True
        elif name == "Read":
            ev["read"] = True
        elif RX_MCP_OPS.search(name):
            # k8s / ClickHouse MCP 查询 = live 证据,且足以充当验证
            ev["live"] = True
            ev["verify"] = True


def _all_labeled(text, claim_rx):
    """断言关键词每一处命中附近(±80)都带标记 → True(视为已诚实标注)。"""
    for m in claim_rx.finditer(text):
        s, e = max(0, m.start() - 80), min(len(text), m.end() + 80)
        if not RX_LABELED.search(text[s:e]):
            return False
    return True


def main():
    if os.environ.get("EVIDENCE_DISCIPLINE_OFF"):
        _pass()          # 逃生阀:EVIDENCE_DISCIPLINE_OFF=1 claude → 本 hook 完全不拦
    raw = sys.stdin.read()
    try:
        data = json.loads(raw) if raw.strip() else {}
    except Exception:
        _pass()
        return

    if data.get("agent_id") or data.get("agent_type"):
        _pass()          # 子 agent 收尾不管
    if data.get("stop_hook_active"):
        _pass()          # 防循环:上一次 block 的续跑不再拦
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
    last_user_text = _text(msgs[last_user][1].get("content")) if last_user >= 0 else ""
    turn = msgs[last_user + 1:] if last_user >= 0 else msgs

    ev = {"live": False, "verify": False, "read": False, "grep": False}
    last_assist = None
    for role, m in turn:
        if role == "assistant":
            last_assist = m
            _scan_tools(m, ev)
    if last_assist is None:
        _pass()

    final_text = _text(last_assist.get("content"))
    if not final_text or not final_text.strip():
        _pass()

    # 上下文闸:非运维/排查语境 → 不启用(Layer-1 的 skill/AGENTS 仍在管)
    ctx = "\n".join([final_text, last_user_text])
    if not RX_OPS.search(ctx):
        _pass()

    investigated = ev["live"] or ev["read"] or ev["grep"]   # 根因:读文件/grep/查 live 都算调查
    problems = []
    if RX_ROOTCAUSE.search(final_text) and not investigated and not _all_labeled(final_text, RX_ROOTCAUSE):
        problems.append("· 给了**根因**,但本轮没有任何调查证据(kubectl / 日志 / ClickHouse / grep / 读文件)支撑它。")
    if RX_LIVE.search(final_text) and not ev["live"] and not _all_labeled(final_text, RX_LIVE):
        problems.append("· 断言了 **pod/运行时的当前状态**,但本轮没有 kubectl / k8s-MCP / 日志命令证明它是 live 状态(而非从 repo/代码推断)。")
    if RX_FIXED.search(final_text) and not ev["verify"] and not _all_labeled(final_text, RX_FIXED):
        problems.append("· 声称 **已修复 / 部署成功 / 已生效**,但本轮没有变更后的验证输出(kubectl rollout status / get pod / --previous 新日志 / 重跑)。")

    if not problems:
        _pass()

    reason = (
        "【evidence-discipline】收尾前发现承重断言缺证据:\n"
        + "\n".join(problems)
        + "\n\n请二选一再收尾:\n"
        "  (A) 现在就跑出能证实它的命令(kubectl / k8s-MCP / 日志 / ClickHouse / 验证命令),用真实输出重写该结论;或\n"
        "  (B) 暂时拿不到证据,就把该句降级标注 [假设] 并紧跟「如何确认: <cmd>」,或标 [未知→查: <cmd>]。\n"
        "铁律:观察→工具输出→结论。别换个说法重申,别用「应该/通常/和另一个服务一样」糊过去。"
    )
    _block(reason)


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception:
        sys.exit(0)   # 兜底 fail-open

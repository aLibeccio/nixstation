#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
evidence-discipline 共享判定核心 (Claude + Codex)
================================================
承重断言正则、运维语境闸、证据命令正则,以及 build_problems()/reason_text()。
两个 runtime 的 entrypoint(Claude stop-verify.py / Codex codex-stop.py)都 import 这里,
保证「判定逻辑」一份 source-of-truth、不漂移。

证据「采集」方式各端不同(Claude 解析 transcript JSONL 的 tool_use;Codex 原文 grep
transcript),但「判定」(三类承重断言 + 证据标志 → 问题列表 → block 文案)共享。

stdlib-only,无第三方依赖。
"""
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

# —— 证据探测:命令字符串 ——
RX_LIVE_CMD = re.compile(r"\bkubectl\b|\baws\s|clickhouse|clickhouse-client|\bpsql\b|\bmysql\b|\bjournalctl\b| logs?\b|describe|\bSELECT\s", re.I)
RX_VERIFY_CMD = re.compile(r"kubectl\s+rollout|kubectl\s+get\s+pods?|kubectl\s+describe|kubectl\s+top|--previous|\bcurl\b|重跑|重新跑|re-?run", re.I)
RX_GREP_CMD = re.compile(r"\bgrep\b|\brg\b|\bawk\b|\bsed\b", re.I)
# —— 证据探测:MCP 工具名(只读 kubernetes / clickhouse MCP)——
RX_MCP_OPS = re.compile(r"kubernetes|kube|clickhouse", re.I)

RX_LABELED = re.compile(r"\[\s*(实测|推断|假设|未知)")


def text_of(content):
    """把 message content(str 或 block 列表)规约成纯文本。"""
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


def all_labeled(text, claim_rx):
    """断言关键词每一处命中附近(±80 字符)都带 [实测]/[推断]/[假设]/[未知] → True
    (视为已诚实标注,放行)。"""
    for m in claim_rx.finditer(text):
        s, e = max(0, m.start() - 80), min(len(text), m.end() + 80)
        if not RX_LABELED.search(text[s:e]):
            return False
    return True


def build_problems(final_text, ev):
    """对最终回答里三类承重断言逐一判定,返回「缺证据」的问题列表(空 = 放行)。

    ev: {"live","verify","read","grep"} 证据标志,由各端证据采集填充:
        live  = 跑过 kubectl/日志/ClickHouse/k8s-MCP 等查 live 状态的命令
        verify= 跑过变更后验证命令(rollout status / get pod / --previous / 重跑)
        read  = 读过真实文件
        grep  = 跑过 grep/rg/awk/sed
    """
    investigated = ev.get("live") or ev.get("read") or ev.get("grep")
    problems = []
    if RX_ROOTCAUSE.search(final_text) and not investigated and not all_labeled(final_text, RX_ROOTCAUSE):
        problems.append("· 给了**根因**,但本轮没有任何调查证据(kubectl / 日志 / ClickHouse / grep / 读文件)支撑它。")
    if RX_LIVE.search(final_text) and not ev.get("live") and not all_labeled(final_text, RX_LIVE):
        problems.append("· 断言了 **pod/运行时的当前状态**,但本轮没有 kubectl / k8s-MCP / 日志命令证明它是 live 状态(而非从 repo/代码推断)。")
    if RX_FIXED.search(final_text) and not ev.get("verify") and not all_labeled(final_text, RX_FIXED):
        problems.append("· 声称 **已修复 / 部署成功 / 已生效**,但本轮没有变更后的验证输出(kubectl rollout status / get pod / --previous 新日志 / 重跑)。")
    return problems


def reason_text(problems):
    """把问题列表组装成 block reason 文案。

    注:本 harness 覆盖**运维 / 诊断类**承重断言;编码类声明(如「测试通过 / 构建
    成功」)不在覆盖范围(语境闸 RX_OPS 不命中编码语境)——这是有意的范围边界。
    """
    return (
        "【evidence-discipline】收尾前发现承重断言缺证据:\n"
        + "\n".join(problems)
        + "\n\n请二选一再收尾:\n"
        "  (A) 现在就跑出能证实它的命令(kubectl / k8s-MCP / 日志 / ClickHouse / 验证命令),用真实输出重写该结论;或\n"
        "  (B) 暂时拿不到证据,就把该句降级标注 [假设] 并紧跟「如何确认: <cmd>」,或标 [未知→查: <cmd>]。\n"
        "铁律:观察→工具输出→结论。别换个说法重申,别用「应该/通常/和另一个服务一样」糊过去。"
    )

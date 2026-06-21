---
name: evidence-discipline
description: Investigation-and-evidence discipline for bug/incident troubleshooting and fact-checking — ESPECIALLY EKS / Kubernetes Java-service debugging (kubectl / logs / ClickHouse). Use whenever diagnosing an error, root-causing, asserting live cluster/pod/runtime state, verifying a fix or deploy, or stating a factual claim about logs/config/data/code. Enforces: investigate with real tools before asserting; distinguish LIVE vs REPO; cite the command behind every specific value; verify before claiming "fixed/done"; and explicitly mark every non-verified statement with [实测]/[推断]/[假设]/[未知]. Pairs with systematic-debugging / diagnose / diagnose-eks-pod.
---

# Evidence Discipline · 调查取证纪律

`systematic-debugging` / `diagnose` / `diagnose-eks-pod` 告诉你**怎么查**;本 skill 规定你**能断言什么、必须怎么标**。一条铁律:

> **观察 → 工具输出 → 结论。** 只允许「我跑了 X、看到 Y、所以 Z」;禁止「我从代码/拓扑/经验推断 Z」却当事实说。

## 硬规则(违反任意一条 = 不许收尾)

1. **live ≠ repo。** 任何关于 cluster / pod / 节点 / 运行时 / 当前配置的*现状*,只能来自**本轮**真正跑过的 `kubectl` / `aws` / 日志 / ClickHouse,并**贴出命令**。repo 里的 YAML / Apollo / 代码只能说「配置为 X」,绝不能说「现在是 X」。
2. **根因要证据。** 给根因前,先贴证明它的日志行 / 查询结果 / 指标。拿不出 → 标 `[假设]` 并写「如何确认」,不许把假设写成结论。
3. **具体值要出处。** 任何间隔 / 列名 / 超时 / 字节数 / ID / 时间戳 / QPS,必须随附产生它的 `grep` / `SELECT` / `kubectl get`。没跑过就别报数。
4. **「修好了」前必验。** 声称 fix / 部署 / 重启 / 回滚成功前,贴**变更后**的验证输出:`kubectl rollout status`、`kubectl get pod`(看 Restart/Ready)、`--previous` 新日志、或带新基线的重跑。没有验证输出 = 不许说「已解决/已生效」。
5. **时间线纪律。** 区分①事件真正发生的时间 ②症状被暴露/被观测的时间。排查分布式问题时给三个时间戳(因→果→被发现),别把「14:18 超时报错」当成「14:18 才出问题」。
6. **看不见就弃权。** 没有证据时,「我现在不知道,需要跑 `<cmd>` 才能确认」是**正确**回答,不是失败。给出确切命令,别用「应该 / 通常 / 一般来说 / 和另一个服务一样」糊过去。

## 明确标记(回答里这样标 —— 满足你的「明确标记说明」)

已实测、有命令支撑的事实**正常陈述**即可;**任何非实测的句子**必须带下列标记之一:

- `[实测: <cmd>]` —— 来自本轮某条命令输出(被质疑时要能立刻贴出原始输出)。
- `[推断]` —— 由已实测事实做的逻辑推导(注明依据哪条实测)。
- `[假设]` —— 尚未核实的前提;**必须**紧跟「如何确认:`<cmd>`」。
- `[未知→查: <cmd>]` —— 不知道,且给出获取答案的确切命令。

> 只标存疑处即可,实测事实不必加标;但 root cause / live 状态 / 「已修复」三类断言**没有 `[实测]` 就必须降级成 `[假设]`**。

## 被怼「证据 / 你确定 / 你没看 / 根本没」时

不要辩解、不要换个说法重申。立刻:① 承认哪句是推断/假设;② 跑出能证实或证伪它的命令;③ 用命令输出重写结论。一次拿不出证据,就明说拿不出。

## 收尾自检(Stop hook 会强制其中一部分)

- [ ] 回答里每个 root cause / live 状态 / 「已修复」断言,都有本轮命令输出支撑,或已标 `[假设]`?
- [ ] 每个具体数值都贴了产生它的命令?
- [ ] 区分了 live 与 repo?
- [ ] 没有用「应该/通常/一样」替代实测?

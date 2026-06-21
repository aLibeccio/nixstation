<!-- agentmemory-prefer:v1 -->

## 优先用 agentmemory(跨会话 / 跨 agent 长期记忆)

任务开始时,先用 agentmemory 查既往记忆(MCP 工具 `memory_smart_search` / `memory_recall`,或 `/recall` skill):个人偏好、项目约定、架构事实、踩过的坑。产生**耐久**的决定 / 偏好 / 约定 / 架构事实时,用 `memory_save`(或 `/remember`)存进去。agentmemory 是 Claude Code ↔ Codex 共享的长期记忆真源(本地 `:3111`,数据在 `~/data`,跨机同步)。**机密(token / 密码 / 凭据)不要写进去。**

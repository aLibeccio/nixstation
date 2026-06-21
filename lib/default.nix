# 模块注册表 —— 未来加能力的唯一改动点:在下面 modules 里加一行即可。
# flake.nix 用 (import ./lib).modules 取这个列表。
# 路径相对本文件(lib/),故用 ../ 指回仓库根。
{
  modules = [
    ../home # 基础:packages / shell / programs(home-manager 主配置)
    ../modules/agent-harness # 跨 agent harness:agentmemory + headroom 两个 daemon + MCP 注册
    ../modules/homebrew # Brewfile 精简到 cask/字体,运行时交给 Nix
    ../modules/agent-config # Claude/Codex 可复现配置切片(幂等注入,不接管整文件)
    ../modules/evidence-discipline # 调查取证/反幻觉:skill + Codex AGENTS 切片 + Claude Stop hook
    ../modules/agentmemory-prefer # agentmemory 按需优先:本地 embeddings + skills + Codex AGENTS 切片
    ../modules/memory-sync # rclone bisync ~/data 跨设备记忆(agentmemory 共享记忆库)
    # 注:dev-envs 是 flake 的 templates 输出(见 flake.nix),不是 home-manager 模块,不进此列表。
    # ../modules/secrets     # (推迟)sops/age,需要 API key 时再开
  ];
}

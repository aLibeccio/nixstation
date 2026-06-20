# 模块注册表 —— 未来加能力的唯一改动点:在下面 modules 里加一行即可。
# flake.nix 用 (import ./lib).modules 取这个列表。
# 路径相对本文件(lib/),故用 ../ 指回仓库根。
{
  modules = [
    ../home # 基础:packages / shell / programs(home-manager 主配置)
    ../modules/agent-harness # 跨 agent harness:agentmemory + headroom 两个 daemon + MCP 注册
    # ../modules/homebrew    # (后续)Brewfile 精简到 cask/字体
    # ../modules/dev-envs    # (后续)Nix devshell 模板 + direnv
    # ../modules/memory-sync # (后续)rclone bisync ~/data 跨设备记忆
    # ../modules/secrets     # (推迟)sops/age,需要 API key 时再开
  ];
}

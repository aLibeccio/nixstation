{ ... }:
{
  imports = [
    ./packages.nix
    ./shell.nix
    ./programs.nix
    # services.nix 已移到 modules/agent-harness/,在 lib/default.nix 的模块列表里注册
  ];
  # username / homeDirectory 由 flake.nix 注入,这里不写死
  home.stateVersion = "25.05"; # 首次安装的版本,定下后别再改
  programs.home-manager.enable = true; # 提供并自管理 home-manager 命令
}

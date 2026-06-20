{ lib, ... }:
{
  # ── 让 home-manager 接管 zsh,并自动写好各工具的 shell 集成 ──
  programs.zsh = {
    enable = true;

    # 保留你原来的 oh-my-zsh(git 插件;主题留空,提示符交给 starship)
    oh-my-zsh = {
      enable = true;
      plugins = [ "git" ];
      theme = "";
    };

    shellAliases = {
      hms = "home-manager switch --flake ~/nix-config#generic --impure";
    };

    # 原 ~/.zprofile 的内容迁移到这里(登录 shell)
    profileExtra = ''
      # Homebrew (Apple Silicon) — 仅在存在时加载,Linux 上自动跳过
      [ -x /opt/homebrew/bin/brew ] && eval "$(/opt/homebrew/bin/brew shellenv)"
      export PATH="$HOME/.local/bin:$PATH"
    '';

    # 原 ~/.zshrc 自定义内容 + 把 Ctrl-R 固定给 atuin(最后执行,盖过 fzf)
    initContent = lib.mkMerge [
      ''
        export PATH="$HOME/.local/bin:$PATH"
      ''
      (lib.mkAfter ''
        bindkey '^r' atuin-search
      '')
    ];
  };

  # ── 需要 shell 集成才生效的工具,改用 programs.* 声明 ──
  programs.fzf = {
    enable = true;
    enableZshIntegration = true; # Ctrl-T 找文件、Alt-C 进目录
  };

  programs.zoxide = {
    enable = true;
    enableZshIntegration = true; # z / zi 智能跳转
  };

  programs.atuin = {
    enable = true;
    enableZshIntegration = true; # Ctrl-R 搜索历史(可选登录后多设备同步)
  };

  programs.starship = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true; # 进入含 .envrc 的目录自动加载 Nix devShell
  };
}

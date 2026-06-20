{ ... }:
{
  # ── git:声明式管理 ~/.gitconfig ──
  programs.git = {
    enable = true;
    # user.name / user.email 不在此写死(各机身份不同),由本地 ~/.gitconfig 提供。
    settings = {
      alias = {
        st = "status";
        co = "checkout";
        br = "branch";
        lg = "log --oneline --graph --decorate --all";
      };
      init.defaultBranch = "main";
      pull.rebase = true;
      push.autoSetupRemote = true; # 首次 push 自动建立 upstream
    };
  };

  # delta:git diff 高亮(新版 home-manager 已从 programs.git.delta 拆为独立模块)
  programs.delta = {
    enable = true;
    enableGitIntegration = true; # 设为 git 的 diff pager(自动启用已弃用,需显式开启)
  };

  # ── gh:保留 git 凭据助手(否则接管 .gitconfig 会让 HTTPS push 失去鉴权) ──
  programs.gh = {
    enable = true;
    gitCredentialHelper.enable = true;
    settings.git_protocol = "https";
  };

  # ── helix:声明式管理 ~/.config/helix/config.toml ──
  programs.helix = {
    enable = true;
    settings = {
      theme = "catppuccin_mocha"; # 改成任意内置主题即可(:theme 可预览)
      editor = {
        line-number = "relative";
        cursorline = true;
        bufferline = "multiple";
        indent-guides.render = true;
        lsp.display-inlay-hints = true;
      };
    };
    # 给 .nix 文件接上 nixd(LSP:补全/跳转/诊断)+ nixfmt(保存自动格式化)
    languages = {
      language-server.nixd.command = "nixd";
      language = [
        {
          name = "nix";
          auto-format = true;
          formatter.command = "nixfmt";
          language-servers = [ "nixd" ];
        }
      ];
    };
  };

  # ── zellij:声明式管理 ~/.config/zellij/config.kdl ──
  programs.zellij = {
    enable = true;
    # 故意不开 enableZshIntegration —— 否则每开终端都自动进 zellij;按需手动敲 `zellij`
    settings = {
      default_shell = "zsh";
      pane_frames = true;
      # theme = "catppuccin-mocha";  # 想要主题再取消注释(用 zellij 内置主题名)
    };
  };
}

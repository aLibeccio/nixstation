{ config, lib, pkgs, ... }:
let
  home = config.home.homeDirectory;
  isDarwin = pkgs.stdenv.hostPlatform.isDarwin;
in
{
  # ── 跨 agent harness 的两个常驻守护进程(仅 macOS;Linux 用 systemd,这里不定义)──
  #   agentmemory : Claude Code ↔ Codex 共享记忆(REST :3111)
  #   headroom    : 上下文压缩 proxy(:8787),让 claude/codex 透明走压缩
  # 二进制本身不是 nix 包(agentmemory 走 npm -g、headroom 走 uv tool),
  # 由下方 home.activation 幂等安装;这里只声明 launchd 服务。
  launchd.agents = lib.optionalAttrs isDarwin {
    "com.agentmemory.daemon" = {
      enable = true;
      config = {
        ProgramArguments = [ "/opt/homebrew/bin/agentmemory" ];
        EnvironmentVariables = {
          PATH = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin";
          HOME = home;
        };
        WorkingDirectory = home;
        RunAtLoad = true;
        KeepAlive = true;
        ThrottleInterval = 10;
        StandardOutPath = "${home}/.agentmemory/daemon.log";
        StandardErrorPath = "${home}/.agentmemory/daemon.err.log";
      };
    };
    "com.headroom.proxy" = {
      enable = true;
      config = {
        ProgramArguments = [ "${home}/.local/bin/headroom" "proxy" "--port" "8787" ];
        EnvironmentVariables = {
          PATH = "${home}/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin";
          HOME = home;
          HEADROOM_TELEMETRY = "off"; # 关匿名遥测
        };
        WorkingDirectory = home;
        RunAtLoad = true;
        KeepAlive = true;
        ThrottleInterval = 10;
        StandardOutPath = "${home}/.headroom/logs/proxy.daemon.log";
        StandardErrorPath = "${home}/.headroom/logs/proxy.daemon.err.log";
      };
    };
  };

  # ── 幂等安装两个 agent 的二进制 + 建日志目录(仅缺失时装,让新机器可复现)──
  home.activation = lib.optionalAttrs isDarwin {
    harnessServiceDirs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      mkdir -p "$HOME/.headroom/logs" "$HOME/.agentmemory"
    '';
    installHeadroom = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if ! [ -x "$HOME/.local/bin/headroom" ]; then
        echo "[activation] installing headroom via uv (one-time)..."
        ${pkgs.uv}/bin/uv tool install --python 3.13 "headroom-ai[proxy,ml,pytorch-mps]" || true
      fi
    '';
    installAgentmemory = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if ! command -v agentmemory >/dev/null 2>&1 && [ -x /opt/homebrew/bin/npm ]; then
        echo "[activation] installing agentmemory via npm -g (one-time)..."
        /opt/homebrew/bin/npm install -g @agentmemory/agentmemory || true
      fi
    '';
  };
}

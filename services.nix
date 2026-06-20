{ config, lib, pkgs, ... }:
let
  home = config.home.homeDirectory;
  isDarwin = pkgs.stdenv.hostPlatform.isDarwin;
  # 存在性保护:二进制还没装好时(新机首次 hms,uv/npm 安装尚未完成),
  # 不要让 launchd 每 ThrottleInterval 就 crash-loop —— 而是轮询等待最多 ~5 分钟,
  # 二进制一出现立刻 exec;超时才 exit 1 交给 launchd 重试。
  guarded = bin: argsStr:
    [ "/bin/sh" "-c" "for _ in $(seq 1 60); do if [ -x \"${bin}\" ]; then exec \"${bin}\" ${argsStr}; fi; sleep 5; done; echo \"[launchd] ${bin} missing after 5min\"; exit 1" ];
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
        ProgramArguments = guarded "/opt/homebrew/bin/agentmemory" "";
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
        ProgramArguments = guarded "${home}/.local/bin/headroom" "proxy --port 8787";
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

  # ── 幂等安装二进制 + 注册 MCP + 建日志目录(仅缺失时装,让新机器可复现)──
  home.activation = lib.optionalAttrs isDarwin {
    harnessServiceDirs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      mkdir -p "$HOME/.headroom/logs" "$HOME/.agentmemory"
    '';
    installHeadroom = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if ! [ -x "$HOME/.local/bin/headroom" ]; then
        echo "[activation] installing headroom via uv (one-time, pulls PyTorch)..."
        ${pkgs.uv}/bin/uv tool install --python 3.13 "headroom-ai[proxy,ml,pytorch-mps]" || true
      fi
    '';
    installAgentmemory = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if ! command -v agentmemory >/dev/null 2>&1 && [ -x /opt/homebrew/bin/npm ]; then
        echo "[activation] installing agentmemory via npm -g (one-time)..."
        /opt/homebrew/bin/npm install -g @agentmemory/agentmemory || true
      fi
    '';
    # P2: 注册 headroom MCP(CCR 可逆取回)到 Claude Code。codex 的 MCP 由 shell.nix
    # 的 codex() 自愈分支在 provider 注入时一并注册(本版本 `mcp install` 暂不支持 codex)。
    installHeadroomMcpClaude = lib.hm.dag.entryAfter [ "installHeadroom" ] ''
      if [ -x "$HOME/.local/bin/headroom" ]; then
        "$HOME/.local/bin/headroom" mcp install --agent claude --proxy-url http://127.0.0.1:8787 >/dev/null 2>&1 || true
      fi
    '';
  };
}

{
  config,
  lib,
  pkgs,
  ...
}:
let
  home = config.home.homeDirectory;
  isDarwin = pkgs.stdenv.hostPlatform.isDarwin;
  isLinux = pkgs.stdenv.hostPlatform.isLinux;

  # Nix-owned runtime.
  node = pkgs.nodejs_22;
  npmPrefix = "${home}/.npm-global";
  amVersion = "0.9.27"; # pinned version
  amDir = "${npmPrefix}/lib/node_modules/@agentmemory/agentmemory";
  amEntry = "${amDir}/dist/cli.mjs"; # daemon entry
  amBin = "${npmPrefix}/bin/agentmemory"; # CLI entry

  kubernetesMcpSpec = "kubernetes-mcp-server@0.0.63";

  # launchd waits for first install before exec.
  guardedExec = waitFor: cmd: [
    "/bin/sh"
    "-c"
    "for _ in $(seq 1 60); do [ -e \"${waitFor}\" ] && exec ${cmd}; sleep 5; done; echo \"[launchd] ${waitFor} missing after 5min\" >&2; exit 1"
  ];
in
{
  # macOS launchd daemons.
  launchd.agents = lib.optionalAttrs isDarwin {
    "com.agentmemory.daemon" = {
      enable = true;
      config = {
        ProgramArguments = guardedExec amEntry ''"${node}/bin/node" "${amEntry}"'';
        EnvironmentVariables = {
          PATH = "${node}/bin:/usr/bin:/bin:/usr/sbin:/sbin"; # 只给 Nix node,不再含 /opt/homebrew
          HOME = home;
        };
        WorkingDirectory = home; # data resolves under HOME
        RunAtLoad = true;
        KeepAlive = true;
        ThrottleInterval = 10;
        StandardOutPath = "${home}/.agentmemory/daemon.log";
        StandardErrorPath = "${home}/.agentmemory/daemon.err.log";
      };
    };
  };

  # Linux systemd user services.
  # 没有 launchd 的 guarded 轮询;靠 Restart=always 在二进制就绪前不断重试。
  systemd.user.services = lib.optionalAttrs isLinux {
    agentmemory = {
      Unit = {
        Description = "agentmemory cross-agent memory daemon (:3111)";
        After = [ "network.target" ];
      };
      Service = {
        ExecStart = "${node}/bin/node ${amEntry}";
        WorkingDirectory = home;
        Restart = "always";
        RestartSec = 10;
      };
      Install.WantedBy = [ "default.target" ];
    };
  };

  # Install binaries and register MCPs.
  # Activation installers are guarded and idempotent.
  home.activation = {
    harnessServiceDirs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      mkdir -p "$HOME/.agentmemory"
    '';

    # Install pinned agentmemory.
    installAgentmemory = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      have="$(${node}/bin/node -e 'try{process.stdout.write(require("${amDir}/package.json").version)}catch(e){process.stdout.write("none")}' 2>/dev/null || echo none)"
      if [ "$have" != "${amVersion}" ]; then
        echo "[activation] installing @agentmemory/agentmemory@${amVersion} via Nix npm -> ${npmPrefix} (have=$have)..."
        # postinstall expects node on PATH.
        PATH="${node}/bin:$PATH" ${node}/bin/npm install -g --prefix "${npmPrefix}" "@agentmemory/agentmemory@${amVersion}" || true
      fi
    '';

    # Register harness MCPs for Claude and Codex.
    registerHarnessMcps = lib.hm.dag.entryAfter [ "installAgentmemory" ] ''
      # Codex needs node during activation.
      export PATH="${node}/bin:$PATH"
      C="$HOME/.local/bin/claude"
      # Probe common codex locations.
      X=""; for c in "$HOME/.npm-global/bin/codex" "$HOME/.local/bin/codex" "$(command -v codex 2>/dev/null)" /opt/homebrew/bin/codex /usr/local/bin/codex; do [ -n "$c" ] && [ -x "$c" ] && { X="$c"; break; }; done
      AM="${amBin}"
      K8S_MCP_SPEC="${kubernetesMcpSpec}"
      CJ="$HOME/.claude.json"; CT="$HOME/.codex/config.toml"
      # agentmemory(记忆)
      if [ -x "$AM" ]; then
        grep -q '"agentmemory"' "$CJ" 2>/dev/null || "$AM" connect claude-code >/dev/null 2>&1 || true
        grep -q 'mcp_servers.agentmemory' "$CT" 2>/dev/null || "$AM" connect codex >/dev/null 2>&1 || true
      fi
      # context7 docs and Kubernetes MCPs.
      if [ -x "$C" ]; then
        grep -q '"context7"' "$CJ" 2>/dev/null || "$C" mcp add -s user context7 -- npx -y @upstash/context7-mcp >/dev/null 2>&1 || true
        if ! grep -q '"kubernetes"' "$CJ" 2>/dev/null; then
          "$C" mcp add -s user kubernetes -- npx -y "$K8S_MCP_SPEC" >/dev/null 2>&1 || true
        elif grep -q '"--read-only"' "$CJ" 2>/dev/null || grep -q 'kubernetes-mcp-server@latest' "$CJ" 2>/dev/null; then   # repair stale registration
          "$C" mcp remove -s user kubernetes >/dev/null 2>&1 || true
          "$C" mcp add -s user kubernetes -- npx -y "$K8S_MCP_SPEC" >/dev/null 2>&1 || true
        fi
      fi
      if [ -x "$X" ]; then
        grep -q 'mcp_servers.context7' "$CT" 2>/dev/null || "$X" mcp add context7 -- npx -y @upstash/context7-mcp >/dev/null 2>&1 || true
        if ! grep -q 'mcp_servers.kubernetes' "$CT" 2>/dev/null; then
          "$X" mcp add kubernetes -- npx -y "$K8S_MCP_SPEC" >/dev/null 2>&1 || true
        elif grep -q -- '--read-only' "$CT" 2>/dev/null || grep -q 'kubernetes-mcp-server@latest' "$CT" 2>/dev/null; then   # repair stale registration
          "$X" mcp remove kubernetes >/dev/null 2>&1 || true
          "$X" mcp add kubernetes -- npx -y "$K8S_MCP_SPEC" >/dev/null 2>&1 || true
        fi
      fi
    '';
  };
}

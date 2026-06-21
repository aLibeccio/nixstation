{ config, lib, pkgs, ... }:
# Sync agentmemory data with rclone bisync.
# Data and rclone credentials stay outside Git.
# First run uses --resync; later runs resolve conflicts by newer mtime.
let
  home = config.home.homeDirectory;
  isDarwin = pkgs.stdenv.hostPlatform.isDarwin;
  isLinux = pkgs.stdenv.hostPlatform.isLinux;

  # Sync settings.
  remote = "agentmemory"; # rclone remote name.
  remotePath = "agentmemory:agentmemory-data"; # Remote data path.
  localDir = "${home}/data"; # agentmemory data directory.
  stateDir = "${home}/.agentmemory"; # state and logs.
  initMarker = "${stateDir}/.bisync-initialized"; # first-run marker.
  logFile = "${stateDir}/rclone-bisync.log"; # rclone log.

  # rclone bisync script.
  rclone = "${pkgs.rclone}/bin/rclone";
  coreutils = pkgs.coreutils;
  syncScript = pkgs.writeShellScript "agentmemory-bisync" ''
    set -u
    RCLONE=${rclone}
    PATH=${coreutils}/bin:$PATH   # date/mkdir/touch/test 等,确保最小环境下也能跑
    export PATH

    LOG=${logFile}
    mkdir -p ${stateDir} ${localDir}

    log() { echo "[$(date '+%Y-%m-%dT%H:%M:%S%z')] $*" >> "$LOG"; }

      # No configured remote: no-op.
    if ! "$RCLONE" listremotes 2>/dev/null | grep -qx '${remote}:'; then
      log "remote '${remote}:' 未配置(rclone config 缺失),跳过同步(no-op)"
      exit 0
    fi

      # Shared rclone flags.
    COMMON="--log-file=$LOG --log-level INFO"

    if [ ! -f ${initMarker} ]; then
      # First run: create baseline.
      log "首次同步:rclone bisync --resync(以本地 ${localDir} 为基准建立基线)"
      if "$RCLONE" bisync ${localDir} ${remotePath} --resync $COMMON; then
        touch ${initMarker}
        log "首次 --resync 成功,已写标记 ${initMarker}"
      else
        log "首次 --resync 失败(保留无标记,下次重试);见上方 rclone 日志"
        exit 1
      fi
    else
      # Normal run: two-way sync.
      log "常规同步:rclone bisync --resilient --conflict-resolve newer"
      if "$RCLONE" bisync ${localDir} ${remotePath} --resilient --conflict-resolve newer $COMMON; then
        log "常规 bisync 成功"
      else
          # Keep marker on failure; logs show manual repair command.
        log "常规 bisync 失败:基线可能损坏,可手动跑一次 --resync 修复;见上方 rclone 日志"
        exit 1
      fi
    fi
  '';
in
{
  # Ensure state directories.
  home.activation.memorySyncDirs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p "${stateDir}" "${localDir}"
  '';

  # macOS launchd timer.
  launchd.agents = lib.optionalAttrs isDarwin {
    "com.agentmemory.bisync" = {
      enable = true;
      config = {
        ProgramArguments = [ "${syncScript}" ];
        EnvironmentVariables = {
          # Fallback process environment.
          PATH = "${coreutils}/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin";
          HOME = home;
        };
        WorkingDirectory = home;
        RunAtLoad = true; # run on load
        StartInterval = 900; # every 15 minutes
        # launchd stdio fallback.
        StandardOutPath = "${stateDir}/bisync.launchd.log";
        StandardErrorPath = "${stateDir}/bisync.launchd.err.log";
      };
    };
  };

  # Linux systemd user timer.
  systemd.user.services = lib.optionalAttrs isLinux {
    "agentmemory-bisync" = {
      Unit = {
        Description = "agentmemory 共享记忆库 ~/data 的 rclone bisync 同步";
        # 弱依赖网络(user 级 network-online 不一定存在,故不强 Requires)。
        After = [ "network-online.target" ];
        Wants = [ "network-online.target" ];
      };
      Service = {
        Type = "oneshot";
        ExecStart = "${syncScript}";
        # 没配 remote 时脚本 exit 0,systemd 视为成功 → no-op,不报错。
      };
    };
  };
  systemd.user.timers = lib.optionalAttrs isLinux {
    "agentmemory-bisync" = {
      Unit.Description = "定时触发 agentmemory ~/data bisync(每 15 分钟)";
      Timer = {
        OnBootSec = "5min"; # 开机/登录后 5 分钟先跑一次
        OnUnitActiveSec = "15min"; # 之后每 15 分钟一次
        Persistent = true; # 错过的触发在唤醒后补跑
      };
      Install.WantedBy = [ "timers.target" ];
    };
  };
}

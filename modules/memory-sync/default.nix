{ config, lib, pkgs, ... }:
# ─────────────────────────────────────────────────────────────────────────────
#  memory-sync 模块 —— 跨设备同步 agentmemory 的共享记忆库 ~/data
# ─────────────────────────────────────────────────────────────────────────────
#
#  ■ 这是什么
#    agentmemory 守护进程(:3111,见 modules/agent-harness)把 Claude Code ↔ Codex
#    的「共享长期记忆」落盘在 ~/data/ 下:
#       ~/data/state_store.db/   ← 文件型 KV(remember/recall 的事实)
#       ~/data/stream_store/     ← 事件流
#    本模块周期性地把 ~/data 与一个云端 remote 双向同步(rclone bisync),
#    于是在 A 机 `remember` 的事实,过一会儿能在 B 机 `recall` 命中 —— 记忆跟着人走。
#
#  ■ 为什么数据走「单独通道」、永远不进 git 仓库
#    ~/data 是「数据」不是「配置」:它体积会增长、是二进制 KV/事件流、且含个人记忆
#    内容(可能敏感)。把它塞进这个 public GitHub 仓库既不合适也不安全,而且 git 对
#    频繁变动的二进制库支持很差(无法增量 diff、仓库会膨胀)。所以:
#       - 配置(本 .nix 文件)→ 进仓库,随 home-manager 复现到每台机器;
#       - 数据(~/data)      → 只走本模块这条 rclone bisync 通道,绝不进仓库。
#    顺带:headroom 的 ~/.headroom/(日志/指标)是「机器本地」语义,既不进仓库
#    也不在此同步 —— 它本就该每台机器各自独立。本模块只碰 ~/data。
#
#  ■ 为什么先选 rclone bisync,而不是 agentmemory 自带的 P2P mesh
#    agentmemory 据称支持节点间 P2P mesh 同步,但 mesh 要求「两台机器同时在线」才能
#    对等传播。多设备日常场景里这点很难保证(笔记本合盖、台式机关机)。
#    rclone bisync 走「云端 remote 中转」:任意一台机器单独在线时,把本地 ~/data 与
#    云端对一次账即可,落地、再上去都行 —— 异步、单机在线即可,鲁棒得多。
#    因此先用 bisync 打底;agentmemory 的 P2P mesh 留作后续(等需要近实时再叠加)。
#
#  ■ 冲突风险与 --resync 语义(重要)
#    bisync 是「双向」同步:两端都可写。若 A、B 两机在「上一次成功对账之后、下一次
#    对账之前」各自修改了同一条记忆,就会产生冲突。本模块的策略:
#       常规跑:--resilient --conflict-resolve newer
#               → newer:发生冲突时按修改时间取「较新」的一份为准(对单人多设备、
#                 同一时刻通常只在一台机器上操作的场景,够用且不丢「最新意图」)。
#               → resilient:遇到可恢复的错误(如某次中断)不直接放弃,尽量自愈。
#       首次跑:--resync
#               ⚠ --resync 不是「双向合并」!它把「以本地 ~/data 为基准」建立同步基线,
#                 会让远端向本地看齐(远端独有、且本地没有的文件可能被清理)。所以
#                 --resync 只能在「确知哪一端是权威初始数据」时跑一次。本模块用一个
#                 标记文件区分首次/常规(见 syncScript),保证 --resync 只在初始化时
#                 发生一次,之后永远走常规双向 bisync,既幂等又安全。
#    并发写风险无法被 bisync 完全消除:理想情况下「同步前让 agentmemory 落盘一致」会更
#    稳(例如先 flush/静默写入),但这里不强求 —— daemon 持续在写,bisync 的冲突策略
#    就是用来兜这种情况的。若未来记忆写入很频繁,可考虑同步时短暂 pause daemon。
#
#  ■ secret 说明(本项目第一个真正的 secret)
#    rclone remote 的凭据(token / access key)是这个仓库里第一个真正意义上的 secret。
#    现状:由用户手动 `rclone config` 配置名为 `agentmemory:` 的 remote,凭据写入
#          ~/.config/rclone/rclone.conf —— 该文件「机器本地、不进仓库」,所以 secret
#          不会泄漏到 public GitHub。每台新机器各自跑一次 `rclone config` 即可。
#    未来:可用 sops-nix / agenix 把 rclone.conf(或其中的 token)纳入加密管理,随仓库
#          分发到各机解密落地 —— 对应 lib/default.nix 里预留的 ../modules/secrets。
#          在那之前,本模块对「没配 remote 的机器」整体 no-op(见守卫),不会报错。
#
let
  home = config.home.homeDirectory;
  isDarwin = pkgs.stdenv.hostPlatform.isDarwin;
  isLinux = pkgs.stdenv.hostPlatform.isLinux;

  # 同步约定 —— 改这里即可调整源/远端/周期。
  remote = "agentmemory"; # `rclone config` 里要建的 remote 名(脚本会拼成 agentmemory:)
  remotePath = "agentmemory:agentmemory-data"; # 云端落地路径(remote 下的目录)
  localDir = "${home}/data"; # 本地共享记忆库(agentmemory 的数据目录)
  stateDir = "${home}/.agentmemory"; # 标记文件 + 日志放这(与 agent-harness 同目录)
  initMarker = "${stateDir}/.bisync-initialized"; # 区分「首次 --resync」与「常规 bisync」
  logFile = "${stateDir}/rclone-bisync.log"; # rclone 日志

  # 同步脚本(纯 store-path 引用二进制,不依赖 launchd/systemd 那套精简 PATH)。
  #   - 守卫:listremotes 里没有 `agentmemory:` 就直接 exit 0 → 没配 remote 的机器 no-op。
  #   - 幂等:首次(无 initMarker)走 --resync 建基线,成功后 touch 标记;之后走常规 bisync。
  #   - 日志:全部 append 到 ~/.agentmemory/rclone-bisync.log。
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

    # ── 守卫:没配 `${remote}:` remote(新机 / CI / 还没 rclone config)→ 静默 no-op ──
    if ! "$RCLONE" listremotes 2>/dev/null | grep -qx '${remote}:'; then
      log "remote '${remote}:' 未配置(rclone config 缺失),跳过同步(no-op)"
      exit 0
    fi

    # 公共 flags:--log-file 让 rclone 自身的进度/错误也进同一份日志。
    COMMON="--log-file=$LOG --log-level INFO"

    if [ ! -f ${initMarker} ]; then
      # ── 首次:建立同步基线。--resync 以本地 ${localDir} 为基准,不是双向合并 ──
      log "首次同步:rclone bisync --resync(以本地 ${localDir} 为基准建立基线)"
      if "$RCLONE" bisync ${localDir} ${remotePath} --resync $COMMON; then
        touch ${initMarker}
        log "首次 --resync 成功,已写标记 ${initMarker}"
      else
        log "首次 --resync 失败(保留无标记,下次重试);见上方 rclone 日志"
        exit 1
      fi
    else
      # ── 常规:双向 bisync。newer = 冲突按修改时间取较新;resilient = 尽量自愈 ──
      log "常规同步:rclone bisync --resilient --conflict-resolve newer"
      if "$RCLONE" bisync ${localDir} ${remotePath} --resilient --conflict-resolve newer $COMMON; then
        log "常规 bisync 成功"
      else
        # 常规 bisync 失败常因基线损坏(例如上次中断)。不 touch、不删标记,
        # 留给用户在日志里看到提示后,必要时手动 `rclone bisync ... --resync` 修复。
        log "常规 bisync 失败:基线可能损坏,可手动跑一次 --resync 修复;见上方 rclone 日志"
        exit 1
      fi
    fi
  '';
in
{
  # 公共:确保状态目录存在(日志/标记文件的家);两个平台都需要。
  home.activation.memorySyncDirs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p "${stateDir}" "${localDir}"
  '';

  # ── macOS:launchd agent,每 StartInterval 秒跑一次同步脚本 ──
  # 注:optionalAttrs 放在 value 里(launchd/systemd 顶层 key 固定),不能在顶层 mkMerge
  #     里按 pkgs 条件增删属性,否则「模块声明哪些属性」依赖 pkgs → 无限递归。
  launchd.agents = lib.optionalAttrs isDarwin {
    "com.agentmemory.bisync" = {
      enable = true;
      config = {
        ProgramArguments = [ "${syncScript}" ];
        EnvironmentVariables = {
          # 脚本内部已用 store-path 引用二进制,这里给个保底 PATH + HOME 即可。
          PATH = "${coreutils}/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin";
          HOME = home;
        };
        WorkingDirectory = home;
        RunAtLoad = true; # 登录/加载即对一次账
        StartInterval = 900; # 之后每 900 秒(15 分钟)一次
        # 脚本自己写 ~/.agentmemory/rclone-bisync.log;这里再兜住 launchd 层面的 stdio。
        StandardOutPath = "${stateDir}/bisync.launchd.log";
        StandardErrorPath = "${stateDir}/bisync.launchd.err.log";
      };
    };
  };

  # ── Linux:systemd user service(oneshot)+ timer(每 15 分钟触发)──
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

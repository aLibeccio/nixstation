{ config, lib, pkgs, ... }:
# agentmemory-prefer —— 让 agentmemory 成为「按需优先」的跨 agent 长期记忆。
# 全部幂等、通用、且**不把任何记忆内容写进仓库**(nixstation 是公开 repo):
#   ① .env:EMBEDDING_PROVIDER=local(本地离线 embeddings)+ BM25_WEIGHT=0.6(关键词/向量平衡)。
#   ② patch 本地模型 → 多语言版(让 MiniLM 支持中文;agentmemory 把模型写死、无 env,只能改包)。
#   ③ 缺则装 agentmemory 的 skills(/recall /remember …)到 ~/.agents/skills。
#   ④ 往 Codex 的 ~/.codex/AGENTS.md 注入「先查 agentmemory」切片(守卫式 append)。
# 记忆数据本身(精选事实 + 多语言 embedding)经既有 rclone bisync(modules/memory-sync)跨机同步,不进 git。
# Claude 侧的「优先」靠:已注册的 agentmemory MCP + 装好的 skills + file-memory 里的 prefer 条目。
let
  node = pkgs.nodejs_22;
  home = config.home.homeDirectory;
  isDarwin = pkgs.stdenv.hostPlatform.isDarwin;
  amEnv = "${home}/.agentmemory/.env";
  amDist = "${home}/.npm-global/lib/node_modules/@agentmemory/agentmemory/dist";
  # patch 模型 / 改 .env 后重启 agentmemory daemon(平台分流),失败不阻断 hms。
  restartDaemon =
    if isDarwin
    then ''/bin/launchctl kickstart -k "gui/$(id -u)/org.nix-community.home.com.agentmemory.daemon" >/dev/null 2>&1 || true''
    else ''systemctl --user restart agentmemory >/dev/null 2>&1 || true'';
in
{
  home.activation = {
    # ① agentmemory .env —— daemon 读 ~/.agentmemory/.env;每个 key 只在缺失时补,绝不覆盖用户已有值。
    #   EMBEDDING_PROVIDER=local : 本地离线 embeddings(Xenova MiniLM),不外发任何数据。
    #   BM25_WEIGHT=0.6          : jieba 中文关键词 与 多语言向量 的平衡点(实测 0.6 关键词召回最强,
    #                              又给向量留足跨语言语义召回空间;<0.6 关键词精度掉,>0.6 语义余量变少)。
    agentmemoryEnv = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      ENV="${amEnv}"
      mkdir -p "$(dirname "$ENV")"; [ -f "$ENV" ] || : > "$ENV"
      ensure() {  # $1=KEY $2=VALUE $3=注释 —— 缺 KEY 才补,已有用户值则 no-op
        if grep -qE "^[[:space:]]*$1[[:space:]]*=" "$ENV"; then
          echo "[agentmemory-prefer] $1 已存在,no-op"
        else
          [ -n "$3" ] && printf '# %s\n' "$3" >> "$ENV"
          printf '%s=%s\n' "$1" "$2" >> "$ENV"
          echo "[agentmemory-prefer] 已设 $1=$2(需重启 agentmemory daemon 生效)"
        fi
      }
      ensure EMBEDDING_PROVIDER local "local offline embeddings (Xenova MiniLM); no external calls"
      ensure BM25_WEIGHT 0.6 "balance jieba keyword + multilingual vector recall"
    '';

    # ② patch 本地 embedding 模型 → 多语言版,让本地 MiniLM 支持中文(跨语言语义召回)。
    #    agentmemory 这版把模型名写死在 dist、无 env 开关,只能改包。幂等:已 patch 则 no-op;
    #    找不到目标串则**大声 WARN**(上游升级改了实现)。改动后重启 daemon 重载(首次下 ~120MB)。
    #    entryAfter installAgentmemory:万一 amVersion 被 bump 重装,本步会重新打上 patch。
    #    注:换模型后旧 embedding 作废;本机已重 embed,跨机靠同步的 ~/data(已是多语言 embedding)保持一致。
    agentmemoryPatchModel = lib.hm.dag.entryAfter [ "writeBoundary" "installAgentmemory" ] ''
      DIST="${amDist}"; OLD="Xenova/all-MiniLM-L6-v2"; NEW="Xenova/paraphrase-multilingual-MiniLM-L12-v2"
      if [ ! -d "$DIST" ]; then
        echo "[agentmemory-prefer] $DIST 不存在,跳过模型 patch"
      else
        hits=$(${pkgs.gnugrep}/bin/grep -rlF --include='*.mjs' "$OLD" "$DIST" 2>/dev/null || true)
        if [ -n "$hits" ]; then
          printf '%s\n' "$hits" | while IFS= read -r f; do ${pkgs.gnused}/bin/sed -i "s|$OLD|$NEW|g" "$f"; done
          echo "[agentmemory-prefer] 已 patch embedding 模型 → 多语言 MiniLM,重启 daemon"
          ${restartDaemon}
        elif ${pkgs.gnugrep}/bin/grep -rlqF --include='*.mjs' "$NEW" "$DIST" 2>/dev/null; then
          echo "[agentmemory-prefer] 多语言模型 patch 已在,no-op"
        else
          echo "[agentmemory-prefer][WARN] dist 里既无 $OLD 也无 $NEW —— agentmemory 可能升级且改了实现,模型 patch 未生效,请人工检查!"
        fi
      fi
    '';

    # ③ agentmemory skills —— 缺 recall 才装;从 $HOME 跑,避免被装进某个 repo 的 .agents/。
    #    networked:离线/失败时 || true 静默跳过,不阻断 hms。
    agentmemorySkills = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if [ -e "$HOME/.agents/skills/recall" ]; then
        echo "[agentmemory-prefer] agentmemory skills 已在,no-op"
      else
        echo "[agentmemory-prefer] 安装 agentmemory skills(npx skills add)…"
        ( cd "$HOME" && ${node}/bin/npx -y skills add rohitg00/agentmemory -y ) >/dev/null 2>&1 \
          && echo "[agentmemory-prefer] skills 已装到 ~/.agents/skills" \
          || echo "[agentmemory-prefer] skills 安装失败(离线?),跳过"
      fi
    '';

    # ④ Codex AGENTS.md 切片 —— 守卫式 append,只补一次,不动原有内容;文件不存在则跳过。
    agentmemoryCodexAgents = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      AG="$HOME/.codex/AGENTS.md"; MARK="agentmemory-prefer:v1"
      if [ ! -f "$AG" ]; then
        echo "[agentmemory-prefer] $AG 不存在,跳过 Codex 切片"
      elif grep -qF "$MARK" "$AG" 2>/dev/null; then
        echo "[agentmemory-prefer] AGENTS.md 切片已存在,no-op"
      else
        { printf '\n'; cat ${./assets/AGENTS.snippet.md}; } >> "$AG" \
          && echo "[agentmemory-prefer] 已追加 Codex AGENTS.md 切片" \
          || echo "[agentmemory-prefer] 写 AGENTS.md 失败"
      fi
    '';
  };
}

{ config, lib, pkgs, ... }:
# agentmemory-prefer —— 让 agentmemory 成为「按需优先」的跨 agent 长期记忆。
# 三件事,全部幂等、全部通用、且**不把任何记忆内容写进仓库**(nixstation 是公开 repo):
#   ① 开本地离线 embeddings(EMBEDDING_PROVIDER=local)→ 语义检索,不外发任何数据。
#   ② 缺则装 agentmemory 的 skills(/recall /remember …)到 ~/.agents/skills。
#   ③ 往 Codex 的 ~/.codex/AGENTS.md 注入「先查 agentmemory」切片(守卫式 append)。
# 记忆数据本身(含精选事实)经既有 rclone bisync(modules/memory-sync)跨机同步,不进 git。
# Claude 侧的「优先」靠:已注册的 agentmemory MCP + 装好的 skills + file-memory 里的 prefer 条目。
let
  node = pkgs.nodejs_22;
  amEnv = "${config.home.homeDirectory}/.agentmemory/.env";
in
{
  home.activation = {
    # ① agentmemory .env —— daemon 读 ~/.agentmemory/.env;每个 key 只在缺失时补,绝不覆盖用户已有值。
    #   EMBEDDING_PROVIDER=local : 本地离线 embeddings(Xenova MiniLM),不外发任何数据。
    #   BM25_WEIGHT=0.8          : 本地 MiniLM 是英文模型,对中文 query 基本是噪声;调高 BM25 权重,
    #                              让中文召回靠 jieba 关键词命中(配合 memory 内容里的中文)。实测:
    #                              中文概念查询从基本召回不到 → 全部 rank-1 命中,英文召回基本不受影响。
    #                              (A/B 测 0.8/0.85/0.9 召回完全相同,取 0.8 保留更多语义余量。)
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
      ensure BM25_WEIGHT 0.8 "favor jieba keyword recall (local MiniLM is English-only; high BM25 makes Chinese recall hit)"
    '';

    # ② agentmemory skills —— 缺 recall 才装;从 $HOME 跑,避免被装进某个 repo 的 .agents/。
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

    # ③ Codex AGENTS.md 切片 —— 守卫式 append,只补一次,不动原有内容;文件不存在则跳过。
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

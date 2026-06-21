{ config, lib, pkgs, ... }:
# agentmemory-prefer: prefer shared memory without storing data in Git.
# Managed pieces: env defaults, embedding patch, skills, and Codex snippet.
# Data sync is handled by modules/memory-sync.
let
  node = pkgs.nodejs_22;
  home = config.home.homeDirectory;
  isDarwin = pkgs.stdenv.hostPlatform.isDarwin;
  amEnv = "${home}/.agentmemory/.env";
  amDist = "${home}/.npm-global/lib/node_modules/@agentmemory/agentmemory/dist";
  # Restart daemon after env/model changes.
  restartDaemon =
    if isDarwin
    then ''/bin/launchctl kickstart -k "gui/$(id -u)/org.nix-community.home.com.agentmemory.daemon" >/dev/null 2>&1 || true''
    else ''systemctl --user restart agentmemory >/dev/null 2>&1 || true'';
in
{
  home.activation = {
    # agentmemory .env defaults.
    agentmemoryEnv = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      ENV="${amEnv}"
      mkdir -p "$(dirname "$ENV")"; [ -f "$ENV" ] || : > "$ENV"
      ensure() {  # $1=KEY $2=VALUE $3=COMMENT; no overwrite
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

    # Patch embedding model and reapply after package upgrades.
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

    # Install agentmemory skills when missing.
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

    # Append the Codex snippet once.
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

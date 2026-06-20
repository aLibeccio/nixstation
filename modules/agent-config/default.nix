{ config, lib, pkgs, ... }:
# ─────────────────────────────────────────────────────────────────────────────
# agent-config —— 声明式管理 Claude Code / Codex 里「可复现的配置切片」
#
# 为什么只注入切片、不整文件接管:
#   Claude/Codex 的配置文件把「我们关心的少数配置」和「大量机器本地状态/密钥」
#   混在一起,整文件托管会把机器状态也塞进公开同步的 git 仓库,或在 hms 时把
#   别处写入的状态冲掉。所以这里用幂等 activation 脚本,只「注入并校正」我们
#   在意的那几个 key,其余字节原样不动。
#
#   ~/.claude/settings.json   小,基本是配置,但仍含 skipDangerousModePermissionPrompt
#                             这类本地开关 —— 我们只动 enabledPlugins.superpowers 和 theme。
#   ~/.claude.json            几十个 key:oauthAccount(密钥)、projects、history…
#                             —— 本模块完全不碰(MCP 注册也在 agent-harness 里做)。
#   ~/.codex/config.toml      含 model / model_reasoning_effort(配置)+ headroom proxy
#                             注入块 + [mcp_servers.*](由 agent-harness 注册)+
#                             [projects."<abs-path>"].trust_level(机器本地、跟绝对路径
#                             绑定)+ [marketplaces.*].last_updated(时间戳状态)。
#
#   明确「不纳入」的机器状态/由别处管理的项:
#     • MCP server 注册(agentmemory/headroom/context7/kubernetes)—— 已在
#       modules/agent-harness 用原生 `claude mcp add` / `codex mcp add` 做,本模块不重复。
#     • Codex trust_level —— 跟本机绝对路径(~/.../<user>)绑定,换机器路径就变,不可复现。
#     • headroom proxy / model_provider 注入块 —— 由 headroom 自己的 wrap 动作维护。
#     • oauthAccount / history / projects / marketplaces 时间戳 —— 纯机器状态。
#
# 幂等:每步先读取/比较当前值,已满足则完全 no-op(不写文件、不动 mtime)。
#       老机器上重复 `hms` 不应改动任何配置文件。
# 跨平台:纯配置文件注入,macOS / Linux 都可跑。用文件存在性 + 二进制可执行性守卫;
#         没建过 ~/.codex/config.toml(或 jq 不可用)的机器对应步骤自动跳过。
# ─────────────────────────────────────────────────────────────────────────────
let
  jq = "${pkgs.jq}/bin/jq";

  # Codex 缺失时才补的「合理默认」。只在 key 完全缺失时写入,绝不覆盖用户已有选择。
  # 取舍:model 取一个保守、广泛可用的值;reasoning effort 取中档。换机器后用户随时
  #       可在文件里改成自己想要的(改了之后本模块就不再动它,因为不再缺失)。
  codexDefaultModel = "gpt-5.5";
  codexDefaultReasoningEffort = "medium";
in
{
  home.activation = {
    # ── 1. Claude ~/.claude/settings.json ────────────────────────────────────
    # 确保 enabledPlugins."superpowers@claude-plugins-official" = true 且 theme = "auto"。
    # 只动这两个 key,其它(如 skipDangerousModePermissionPrompt)原样保留。
    # 文件不存在 → 以 {} 起底;用 jq setpath 写到临时文件再 mv(原子替换)。
    # 先比较现值,两个 key 都已满足则不写盘(no-op)。
    claudeSettingsSlice = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      JQ=${lib.escapeShellArg jq}
      SETTINGS="$HOME/.claude/settings.json"
      # 没装 jq 就跳过(理论上 jq 在 home.packages,但保持守卫习惯)。
      if ! [ -x "$JQ" ]; then
        echo "[agent-config] jq 不可用,跳过 Claude settings 注入"
      else
        mkdir -p "$HOME/.claude"
        # 起底:文件不存在/为空时用 {};否则用现有内容(若 JSON 损坏则 jq 读取失败 → 跳过,不破坏文件)。
        if [ -s "$SETTINGS" ]; then
          if ! "$JQ" -e . "$SETTINGS" >/dev/null 2>&1; then
            echo "[agent-config] $SETTINGS 不是合法 JSON,跳过(不覆盖)"
            CUR=""
          else
            CUR=$(cat "$SETTINGS")
          fi
        else
          CUR='{}'
        fi
        if [ -n "''${CUR:-}" ]; then
          # 先判断是否已满足:superpowers 插件为 true 且 theme 为 "auto"。
          if printf '%s' "$CUR" | "$JQ" -e '
                (.enabledPlugins["superpowers@claude-plugins-official"] == true)
                and (.theme == "auto")
              ' >/dev/null 2>&1; then
            : # 已满足,no-op,不写盘
          else
            TMP=$(mktemp "''${SETTINGS}.XXXXXX")
            if printf '%s' "$CUR" | "$JQ" '
                  setpath(["enabledPlugins","superpowers@claude-plugins-official"]; true)
                  | setpath(["theme"]; "auto")
                ' > "$TMP" 2>/dev/null && [ -s "$TMP" ]; then
              mv "$TMP" "$SETTINGS"
              echo "[agent-config] 已更新 Claude settings(superpowers + theme=auto)"
            else
              rm -f "$TMP"
              echo "[agent-config] 写 Claude settings 失败,保持原文件不变"
            fi
          fi
        fi
      fi
    '';

    # ── 2. Codex ~/.codex/config.toml ────────────────────────────────────────
    # 确保 model 与 model_reasoning_effort 存在 —— 但「只在完全缺失时才补默认」。
    # 取舍说明:
    #   * 用户对 model / reasoning effort 的选择是强主观偏好,一旦文件里已有任何值
    #     (哪怕跟我们默认不同)就尊重它、绝不覆盖 → 保证老机器上 hms 是 no-op。
    #   * 只有当 key 在顶层完全缺失时,才补一个保守默认,使「全新机器」也有可用配置。
    #   * trust_level 等跟绝对路径绑定的机器本地配置不在此注入(见顶部注释)。
    #
    # 为什么用 grep 守卫 + 顶部插入,而不是 dasel/toml 编辑:
    #   本机 dasel 是 v3,它把写功能(v1/v2 的 `dasel put`)整个移除了,只剩 query 只读;
    #   所以无法用 dasel 写 TOML。改用 POSIX 工具:grep 探测顶层赋值,缺失时把
    #   `key = "val"` 插到文件最顶端 —— TOML 规定顶层(table 外)键值必须出现在第一个
    #   [table] 头之前,而本文件开头本就是注释/键值区,故「插到最顶端」是唯一合法位置
    #   (追加到 EOF 会落在 [mcp_servers.*] 等表之后,变成非法的顶层键)。整段既有内容
    #   原样保留在新键之后。
    #   守卫正则 `^[[:space:]]*KEY[[:space:]]*=`:KEY 后必须紧跟空白或 `=`,故
    #   `model` 不会误命中 `model_provider`/`model_reasoning_effort`;行首锚定 + 要求
    #   `=`,故 `[model_providers.headroom]` 这类表头、`# model = ...` 注释也不会误命中。
    # 若 config.toml 不存在则不创建(Codex 首次运行会自建;我们不抢先造一个半成品)。
    codexConfigSlice = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      CONFIG="$HOME/.codex/config.toml"
      if ! [ -f "$CONFIG" ]; then
        # 文件不存在 → Codex 还没初始化过,跳过(不创建半成品配置)。
        echo "[agent-config] $CONFIG 不存在,跳过 Codex config 注入"
      else
        # $1=key 名,$2=缺失时要补的默认值。仅当顶层赋值缺失时,把键插到文件最顶端。
        ensure_codex_key() {
          if grep -Eq "^[[:space:]]*$1[[:space:]]*=" "$CONFIG"; then
            : # 顶层已有该键(用户的选择),no-op,不写盘
          else
            TMP=$(mktemp "''${CONFIG}.XXXXXX")
            if { printf '%s = "%s"\n' "$1" "$2"; cat "$CONFIG"; } > "$TMP" && [ -s "$TMP" ]; then
              mv "$TMP" "$CONFIG"
              echo "[agent-config] Codex 缺 $1,已补默认 \"$2\""
            else
              rm -f "$TMP"
              echo "[agent-config] 写 Codex $1 失败,保持原文件不变"
            fi
          fi
        }
        ensure_codex_key model ${lib.escapeShellArg codexDefaultModel}
        ensure_codex_key model_reasoning_effort ${lib.escapeShellArg codexDefaultReasoningEffort}
      fi
    '';
  };
}

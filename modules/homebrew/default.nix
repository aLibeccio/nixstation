{ config, lib, pkgs, ... }:
let
  isDarwin = pkgs.stdenv.hostPlatform.isDarwin;
  home = config.home.homeDirectory;
  # Brewfile 的落盘路径(固定、可预测),activation 步骤按这个绝对路径喂给 brew bundle。
  brewfileDest = ".config/homebrew/Brewfile";
in
# ── Homebrew 模块(仅 macOS)──
#   定位:让 Homebrew 退化成「只管 GUI cask / 字体」的工具,运行时全部交给 Nix。
#   Linux 上整个模块是 no-op(lib.optionalAttrs isDarwin 把两块配置都收成空集),
#   因为 Homebrew 本身就是 macOS-only,Linux 的字体改由 home/packages.nix 里的
#   pkgs.nerd-fonts.meslo-lg 提供。
{
  # 把仓库里的 Brewfile 软链到 ~/.config/homebrew/Brewfile,作为 brew bundle 的唯一真相源。
  # 注:optionalAttrs 必须放在 value 里(home.file / home.activation 等顶层 key 固定),
  #     不能在顶层 mkMerge 里按 isDarwin 增删属性,否则「模块声明哪些属性」依赖 pkgs → 无限递归。
  home.file = lib.optionalAttrs isDarwin {
    ${brewfileDest}.source = ./Brewfile;
  };

  # 幂等应用 Brewfile:每次 hms 都跑,但已装即 no-op。
  home.activation = lib.optionalAttrs isDarwin {
    homebrewBundle = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      # activation 环境的 PATH 很精简,brew 通常不在里面;用绝对路径守卫,
      # brew 没装(例如 CI / 还没装 Homebrew 的新机)就静默跳过,绝不让 hms 失败。
      BREW=/opt/homebrew/bin/brew
      if [ -x "''${BREW}" ]; then
        # 注入 brew 的 shellenv(补 PATH/HOMEBREW_* 环境),再做 bundle。
        eval "$("''${BREW}" shellenv)"
        echo "[activation] brew bundle (cask/字体, --no-upgrade)..."
        # --no-upgrade:已声明且已装的东西保持原状、不主动升级 → 老机器上整体 no-op,
        #              升级动作交给用户显式 `brew upgrade`,避免每次 hms 偷偷拉新版。
        # 刻意 *不* 加 --cleanup:那会卸载所有未在 Brewfile 里声明的 brew 包
        #   (含旧的 node/python/go/mise/gh),太激进。迁移到 Nix 后想清理这些旧 formula,
        #   请自行手动 `brew uninstall node python@3.14 go mise gh` 等,本模块不强制。
        # 直接喂 Nix store 里的 Brewfile(总是存在),避开「activation 早于 linkGeneration、
        # ~/.config/homebrew/Brewfile 软链还没建好」的时序坑。用户侧那份软链仍由 home.file 提供。
        "''${BREW}" bundle --file=${./Brewfile} --no-upgrade || \
          echo "[activation] brew bundle 失败(忽略,不阻断 hms)"
      else
        echo "[activation] 未找到 ''${BREW},跳过 brew bundle(非 macOS 或未装 Homebrew)"
      fi
    '';
  };
}

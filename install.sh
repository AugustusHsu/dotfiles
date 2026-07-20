#!/bin/bash
set -e

DOTFILES="$HOME/code/dotfiles"
LOCAL_BIN="$HOME/.local/bin"

# ============================================================
# 版本鎖定（確保跨機器安裝到一致的版本）
# ============================================================
NVIM_VERSION="v0.12.4"       # Neovim（AppImage，見 install_nvim）
NERD_FONT_VERSION="v3.4.0"   # JetBrainsMono Nerd Font（見 install_nerd_font）
TMUX_VERSION="3.7b"          # tmux（原始碼編譯，見 install_tmux；apt 版本太舊，缺 allow-passthrough 等選項）
# Neovim 外掛的版本鎖定在 nvim/lazy-lock.json（見主流程最後的 lazy restore）

# 走 apt 的相依套件（需自行安裝，缺少會中止並提示）：有對應可執行檔的用 command -v 檢查
declare -A APT_PACKAGE=(
  [git]=git                  # lazy.nvim bootstrap 會 git clone
  [curl]=curl                # 下載字型/nvim/tmux
  [xz]=xz-utils              # 解壓字型的 .tar.xz
  [fc-list]=fontconfig       # 安裝字型後更新快取（fc-list/fc-cache）
  [bison]=bison              # 以下三個是編譯 tmux 用
  [make]=build-essential
  [pkg-config]=pkg-config
)

# 沒有對應可執行檔的 apt 相依套件（tmux 編譯用的開發函式庫），改用 dpkg -s 檢查
APT_LIB_PACKAGES=(libevent-dev libncurses-dev)

# ============================================================
# 函式定義
# ============================================================

# 檢查相依套件是否齊全，缺少就列出安裝指令並中止
check_deps() {
  # ghostty 不在 apt 套件庫（Ubuntu 22.04 沒有這個套件），是 snap 套件，
  # 安裝指令跟其他相依不同，所以獨立檢查、獨立提示
  if ! command -v ghostty >/dev/null 2>&1; then
    echo "缺少 ghostty，請先安裝後再重跑 install.sh："
    echo "  sudo snap install ghostty --classic"
    exit 1
  fi

  local missing=()
  for cmd in "${!APT_PACKAGE[@]}"; do
    command -v "$cmd" >/dev/null 2>&1 || missing+=("${APT_PACKAGE[$cmd]}")
  done
  for pkg in "${APT_LIB_PACKAGES[@]}"; do
    dpkg -s "$pkg" >/dev/null 2>&1 || missing+=("$pkg")
  done
  if [ ${#missing[@]} -gt 0 ]; then
    # 排序後再輸出：bash associative array 的迭代順序不固定，不排序的話
    # 每次執行列出的套件順序都不一樣，不好比對
    local sorted
    mapfile -t sorted < <(printf '%s\n' "${missing[@]}" | sort)
    echo "缺少以下套件，請先手動安裝後再重跑 install.sh："
    echo "  sudo apt install ${sorted[*]}"
    exit 1
  fi
}

# 安裝鎖定版本的 JetBrainsMono Nerd Font 到 ~/.local/share/fonts（供 nvim-web-devicons 圖示用）
install_nerd_font() {
  if fc-list | grep -q "JetBrainsMono Nerd Font Mono"; then
    return
  fi
  echo "安裝 JetBrainsMono Nerd Font $NERD_FONT_VERSION..."
  local tmp
  tmp=$(mktemp -d)
  curl -sL -o "$tmp/JetBrainsMono.tar.xz" \
    "https://github.com/ryanoasis/nerd-fonts/releases/download/$NERD_FONT_VERSION/JetBrainsMono.tar.xz"
  mkdir -p "$HOME/.local/share/fonts"
  tar -xf "$tmp/JetBrainsMono.tar.xz" -C "$HOME/.local/share/fonts"
  fc-cache -f "$HOME/.local/share/fonts" >/dev/null 2>&1
  rm -rf "$tmp"
}

# 用官方 AppImage 裝鎖定版本的 nvim 到 ~/.local/bin（不需 sudo，蓋過 apt 的舊版）
install_nvim() {
  if [ -x "$LOCAL_BIN/nvim" ] && "$LOCAL_BIN/nvim" --version 2>/dev/null | grep -q "$NVIM_VERSION"; then
    return
  fi
  echo "安裝 Neovim $NVIM_VERSION AppImage..."
  mkdir -p "$LOCAL_BIN"
  curl -sL -o "$LOCAL_BIN/nvim.appimage" \
    "https://github.com/neovim/neovim/releases/download/$NVIM_VERSION/nvim-linux-x86_64.appimage"
  chmod +x "$LOCAL_BIN/nvim.appimage"
  ln -sf nvim.appimage "$LOCAL_BIN/nvim"
}

# 原始碼編譯鎖定版本的 tmux 到 ~/.local/bin（不需 sudo，$LOCAL_BIN 在 PATH
# 中排在 apt 的 /usr/bin 前面，會自動蓋過去）；apt（Ubuntu 22.04 只有
# 3.2a）版本太舊，沒有 allow-passthrough 等新選項，見 tmux/tmux.conf
install_tmux() {
  # 守衛只認 $LOCAL_BIN 這一顆（跟 install_nvim 一致），不要用 command -v：
  # command -v 會找到 PATH 上「任何」一顆 tmux，例如手動 sudo make install
  # 裝到 /usr/local/bin 的那種。版本號剛好符合的話守衛就會直接 return，
  # 這段編譯流程永遠不會執行，install.sh 也就永遠補不齊 ~/.local/bin/tmux。
  if [ -x "$LOCAL_BIN/tmux" ] && "$LOCAL_BIN/tmux" -V 2>/dev/null | grep -q "$TMUX_VERSION"; then
    return
  fi
  echo "編譯安裝 tmux $TMUX_VERSION..."
  local tmp
  tmp=$(mktemp -d)
  curl -sL -o "$tmp/tmux.tar.gz" \
    "https://github.com/tmux/tmux/releases/download/$TMUX_VERSION/tmux-$TMUX_VERSION.tar.gz"
  tar -xzf "$tmp/tmux.tar.gz" -C "$tmp"
  (
    cd "$tmp/tmux-$TMUX_VERSION"
    ./configure --prefix="$HOME/.local" >/dev/null
    make -j"$(nproc)" >/dev/null
    make install >/dev/null
  )
  rm -rf "$tmp"
}

# 把設定檔 symlink 到定位；若目標是既有的真實檔案，先搬進 repo 再建 symlink
link() {
  local src="$1" dst="$2"
  mkdir -p "$(dirname "$dst")"
  if [ -e "$dst" ] && [ ! -L "$dst" ]; then
    mv "$dst" "$src"
  fi
  ln -sf "$src" "$dst"
}

# 把所有設定檔連到定位
link_configs() {
  link "$DOTFILES/ghostty/config.ghostty" "$HOME/.config/ghostty/config.ghostty"
  link "$DOTFILES/tmux/tmux.conf" "$HOME/.tmux.conf"
  link "$DOTFILES/nvim/init.lua" "$HOME/.config/nvim/init.lua"
  link "$DOTFILES/nvim/lazy-lock.json" "$HOME/.config/nvim/lazy-lock.json"

  grep -qxF "source $DOTFILES/bash/ide.sh" "$HOME/.bashrc" || \
    echo "source $DOTFILES/bash/ide.sh" >> "$HOME/.bashrc"
}

# 依 lazy-lock.json 鎖定的 commit 還原外掛，確保外掛版本跟這份 dotfiles 一致
restore_nvim_plugins() {
  echo "還原 Neovim 外掛版本（lazy-lock.json）..."
  "$LOCAL_BIN/nvim" --headless -c "lua require('lazy').restore({ wait = true })" -c "qa" 2>&1
}

# ============================================================
# 主流程
# ============================================================
check_deps
install_nerd_font
install_nvim
install_tmux
link_configs
bash "$DOTFILES/gnome/keybindings.sh"
restore_nvim_plugins

echo "install.sh 完成"

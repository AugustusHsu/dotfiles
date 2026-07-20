#!/bin/bash
set -e

# 從腳本自己的位置推導 repo 路徑，不要寫死 ~/code/dotfiles：clone 到其他位置、
# 或用相對路徑執行時一樣正確。先 readlink -f 解開軟連結，否則透過指向這支腳本的
# 軟連結呼叫時，算出來的會是軟連結所在的目錄而不是 repo 目錄。
DOTFILES="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
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
  [python3]=python3          # 讀 claude/mcp-servers.json（見 restore_mcp_servers）
  [bison]=bison              # 以下三個是編譯 tmux 用
  [make]=build-essential
  [pkg-config]=pkg-config
  [xclip]=xclip              # Ghostty/Claude Code 讀寫系統剪貼簿要靠它（X11）；
                              # 沒裝的話終端機貼上剪貼簿內容（含圖片）會完全不動作
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

# 把設定檔 symlink 到定位。
#
# 目標位置已經是 symlink → 直接覆蓋重連即可。
# 目標位置是「真實檔案」時分兩種情況，不能一律搬進 repo：
#   - repo 裡還沒有這份設定 → 搬進 repo（首次把機器上既有的設定收進版控）
#   - repo 裡已經有了 → **絕對不能搬**，那會用這台機器的舊檔覆蓋掉 repo 版本，
#     等於在任何已有設定的新機器上跑 install.sh 都會弄髒/丟失 repo 的內容。
#     改成把機器上既有的檔案備份起來再建 symlink，兩邊內容都不會消失。
link() {
  local src="$1" dst="$2"
  mkdir -p "$(dirname "$dst")"
  if [ -e "$dst" ] && [ ! -L "$dst" ]; then
    if [ -e "$src" ]; then
      local backup="$dst.bak"
      # 已經有 .bak 就加時間戳記，不要蓋掉上一次的備份
      [ -e "$backup" ] && backup="$dst.bak.$(date +%Y%m%d%H%M%S)"
      mv "$dst" "$backup"
      echo "  $dst 已存在且 repo 也有同名設定，原檔備份為 $backup"
    else
      mv "$dst" "$src"
      echo "  $dst 是既有設定且 repo 尚未收錄，已搬進 repo：$src"
    fi
  fi
  ln -sf "$src" "$dst"
}

# 把所有設定檔連到定位
link_configs() {
  link "$DOTFILES/ghostty/config.ghostty" "$HOME/.config/ghostty/config.ghostty"
  link "$DOTFILES/tmux/tmux.conf" "$HOME/.tmux.conf"
  link "$DOTFILES/nvim/init.lua" "$HOME/.config/nvim/init.lua"
  link "$DOTFILES/nvim/lazy-lock.json" "$HOME/.config/nvim/lazy-lock.json"
  link "$DOTFILES/claude/settings.json" "$HOME/.claude/settings.json"
  link "$DOTFILES/claude/CLAUDE.md" "$HOME/.claude/CLAUDE.md"
  link "$DOTFILES/claude/templates/project-CLAUDE.md" "$HOME/.claude/templates/project-CLAUDE.md"

  grep -qxF "source $DOTFILES/bash/ide.sh" "$HOME/.bashrc" || \
    echo "source $DOTFILES/bash/ide.sh" >> "$HOME/.bashrc"
}

# 依 lazy-lock.json 鎖定的 commit 還原外掛，確保外掛版本跟這份 dotfiles 一致
restore_nvim_plugins() {
  echo "還原 Neovim 外掛版本（lazy-lock.json）..."
  "$LOCAL_BIN/nvim" --headless -c "lua require('lazy').restore({ wait = true })" -c "qa" 2>&1
}

# 依 claude/mcp-servers.json 還原 MCP 伺服器（user scope，跨專案都吃得到）。
# claude CLI 不一定裝在這台機器上（dotfiles 本身不負責裝它），沒有就略過，
# 不要讓整個 install.sh 中止。已經存在的同名伺服器也跳過，重跑不會出錯。
restore_mcp_servers() {
  local file="$DOTFILES/claude/mcp-servers.json"
  [ -f "$file" ] || return 0
  if ! command -v claude >/dev/null 2>&1; then
    echo "找不到 claude CLI，略過 MCP 伺服器還原"
    return 0
  fi

  local names existing
  names=$(python3 -c "
import json
print('\n'.join(json.load(open('$file')).get('mcpServers', {})))
")
  [ -z "$names" ] && return 0

  existing=$(claude mcp list 2>/dev/null || true)
  echo "還原 MCP 伺服器（claude/mcp-servers.json）..."
  local name def
  while IFS= read -r name; do
    [ -z "$name" ] && continue
    if printf '%s' "$existing" | grep -q "^$name\b"; then
      echo "  $name 已存在，略過"
      continue
    fi
    def=$(python3 -c "
import json
print(json.dumps(json.load(open('$file'))['mcpServers']['$name']))
")
    # 失敗不要讓整個 install.sh 中止（主流程有 set -e）：MCP 還原是加值步驟，
    # 單一伺服器加不進去時印出訊息繼續跑就好
    if claude mcp add-json --scope user "$name" "$def" >/dev/null 2>&1; then
      echo "  已加入 $name"
    else
      echo "  ⚠ $name 加入失敗，請稍後手動確認：claude mcp add-json --scope user $name '<json>'"
    fi
  done <<< "$names"
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
restore_mcp_servers

echo "install.sh 完成"

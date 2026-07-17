#!/bin/bash
set -e

DOTFILES="$HOME/code/dotfiles"

# nvim 不走 apt（apt 只有 0.9.5，太舊）；改用 AppImage 裝到 ~/.local/bin，見 install_nvim
NVIM_VERSION="v0.12.4"

declare -A APT_PACKAGE=(
  [ghostty]=ghostty
  [tmux]=tmux
  [tree]=tree
  [git]=git
  [curl]=curl
)

check_deps() {
  local missing=()
  for cmd in ghostty tmux tree git curl; do
    command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
  done
  if [ ${#missing[@]} -gt 0 ]; then
    echo "缺少以下套件，請先手動安裝後再重跑 install.sh："
    local pkgs=()
    for cmd in "${missing[@]}"; do
      pkgs+=("${APT_PACKAGE[$cmd]}")
    done
    echo "  sudo apt install ${pkgs[*]}"
    exit 1
  fi
}

check_deps

install_nerd_font() {
  if fc-list | grep -q "JetBrainsMono Nerd Font Mono"; then
    return
  fi
  echo "安裝 JetBrainsMono Nerd Font..."
  local tmp
  tmp=$(mktemp -d)
  curl -sL -o "$tmp/JetBrainsMono.tar.xz" \
    "https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/JetBrainsMono.tar.xz"
  mkdir -p "$HOME/.local/share/fonts"
  tar -xf "$tmp/JetBrainsMono.tar.xz" -C "$HOME/.local/share/fonts"
  fc-cache -f "$HOME/.local/share/fonts" >/dev/null 2>&1
  rm -rf "$tmp"
}

install_nerd_font

install_nvim() {
  # 用官方 AppImage 裝指定版本的 nvim 到 ~/.local/bin（不需 sudo，蓋過 apt 的舊版）
  local bin="$HOME/.local/bin"
  if [ -x "$bin/nvim" ] && "$bin/nvim" --version 2>/dev/null | grep -q "$NVIM_VERSION"; then
    return
  fi
  echo "安裝 Neovim $NVIM_VERSION AppImage..."
  mkdir -p "$bin"
  curl -sL -o "$bin/nvim.appimage" \
    "https://github.com/neovim/neovim/releases/download/$NVIM_VERSION/nvim-linux-x86_64.appimage"
  chmod +x "$bin/nvim.appimage"
  ln -sf nvim.appimage "$bin/nvim"
}

install_nvim

link() {
  local src="$1" dst="$2"
  mkdir -p "$(dirname "$dst")"
  if [ -e "$dst" ] && [ ! -L "$dst" ]; then
    mv "$dst" "$src"
  fi
  ln -sf "$src" "$dst"
}

link "$DOTFILES/ghostty/config.ghostty" "$HOME/.config/ghostty/config.ghostty"
link "$DOTFILES/tmux/tmux.conf" "$HOME/.tmux.conf"
link "$DOTFILES/nvim/init.lua" "$HOME/.config/nvim/init.lua"
link "$DOTFILES/nvim/lazy-lock.json" "$HOME/.config/nvim/lazy-lock.json"

grep -qxF "source $DOTFILES/bash/ide.sh" "$HOME/.bashrc" || \
  echo "source $DOTFILES/bash/ide.sh" >> "$HOME/.bashrc"

bash "$DOTFILES/gnome/keybindings.sh"

# 依 lazy-lock.json 鎖定的版本安裝/還原外掛，確保跟這份 dotfiles 記錄的版本一致
echo "還原 Neovim 外掛版本（lazy-lock.json）..."
"$HOME/.local/bin/nvim" --headless -c "lua require('lazy').restore({ wait = true })" -c "qa" 2>&1

echo "install.sh 完成"

#!/bin/bash
set -e

DOTFILES="$HOME/code/dotfiles"

declare -A APT_PACKAGE=(
  [ghostty]=ghostty
  [tmux]=tmux
  [tree]=tree
  [git]=git
  [nvim]=neovim
)

check_deps() {
  local missing=()
  for cmd in ghostty tmux tree git nvim; do
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

grep -qxF "source $DOTFILES/bash/ide.sh" "$HOME/.bashrc" || \
  echo "source $DOTFILES/bash/ide.sh" >> "$HOME/.bashrc"

bash "$DOTFILES/gnome/keybindings.sh"

echo "install.sh 完成"

ide() {
  local session
  session=$(basename "$PWD" | tr . _)
  if ! tmux has-session -t "$session" 2>/dev/null; then
    # 單一 nvim 全螢幕；neo-tree/編輯器/claude 終端機都在 nvim 內部（toggleterm + edgy）
    # tmux 只當最外層保 session（detach/reattach）
    tmux new-session -d -s "$session" -x "$(tput cols)" -y "$(tput lines)" -c "$PWD" -n main
    tmux send-keys -t "$session:main" 'nvim .' C-m
  fi
  tmux attach -t "$session"
}

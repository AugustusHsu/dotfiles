ide() {
  local session
  # session 名稱 = 資料夾名稱 + 完整路徑的短 hash：只用資料夾名稱的話，
  # 不同路徑但資料夾名稱相同（例如兩個專案都有同名的 backend/ 目錄）會
  # 撞名，誤判成「session 已存在」而直接接回舊路徑開的 session，不是在
  # 目前這個目錄重新開一個。加上路徑 hash 確保不同路徑一定是不同 session。
  session="$(basename "$PWD" | tr . _)-$(echo -n "$PWD" | md5sum | cut -c1-6)"
  if ! tmux has-session -t "$session" 2>/dev/null; then
    # 單一 nvim 全螢幕；neo-tree/編輯器/claude 終端機都在 nvim 內部（toggleterm + edgy）
    # tmux 只當最外層保 session（detach/reattach）
    tmux new-session -d -s "$session" -x "$(tput cols)" -y "$(tput lines)" -c "$PWD" -n main
    tmux send-keys -t "$session:main" 'nvim .' C-m
  fi
  tmux attach -t "$session"
}

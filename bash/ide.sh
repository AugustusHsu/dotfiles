ide() {
  local session cols lines claude_h
  session=$(basename "$PWD" | tr . _)
  if ! tmux has-session -t "$session" 2>/dev/null; then
    cols=$(tput cols)
    lines=$(tput lines)
    claude_h=$(( lines * 30 / 100 ))

    tmux new-session -d -s "$session" -x "$cols" -y "$lines" -c "$PWD" -n main

    # pane 0: nvim（neo-tree 側邊欄 + 編輯區都在內部處理，約 70% 高）
    tmux send-keys -t "$session:main.0" 'nvim .' C-m

    # pane 1: 底部 claude（約 30% 高，用固定行數 -l，因為沒有 client 連著時 -p 百分比會失敗）
    tmux split-window -v -t "$session:main" -c "$PWD" -l "$claude_h"
    tmux send-keys -t "$session:main.1" 'claude' C-m

    # 預設把游標留在 nvim 那格
    tmux select-pane -t "$session:main.0"
  fi
  tmux attach -t "$session"
}

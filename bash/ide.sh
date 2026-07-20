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
    #
    # 直接把 'nvim . ; exec bash' 當成 pane 的啟動指令，而不是用
    # send-keys 模擬打字送進去：send-keys 在 session 剛建立、pane
    # 還沒準備好接收輸入時有 race condition，一旦被其他輸入（例如
    # 滑鼠滾輪誤觸 copy-mode）搶先，指令會被無聲吞掉，畫面就會卡在
    # 空白的 shell、卻沒有任何錯誤訊息。nvim 結束後 exec bash 是為了
    # 離開 nvim 後仍掉回可用的 shell，而不是直接把 session 關掉。
    tmux new-session -d -s "$session" -x "$(tput cols)" -y "$(tput lines)" -c "$PWD" -n main 'nvim . ; exec bash'
    # 存成 session 專屬的 user option，讓 tmux.conf 的 set-titles-string 組出
    # 終端機視窗標題「ide:<資料夾名稱>」。用真正的資料夾名稱（不是拿去算
    # session 名稱、被 tr . _ 處理過的版本），標題才會跟資料夾本身一致。
    tmux set-option -t "$session" @ide_folder "$(basename "$PWD")"
  fi
  tmux attach -t "$session"
}

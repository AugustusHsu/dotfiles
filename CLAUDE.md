# dotfiles — 終端機 IDE

Ghostty + tmux + Neovim 組成的類 VSCode 環境。任一專案下執行 `ide` 開啟。
所有設定用 symlink 納管，`install.sh` 在新機器一鍵重建。

## 指令

```bash
./install.sh          # 完整安裝（可重複執行）
ide                   # 在當前目錄開啟 IDE
```

沒有測試框架。驗證方式是實際開 `ide` 操作，或用 headless nvim（`nvim_input` + 檢查 buffer／extmark）。

## 架構

- **設定檔都是 symlink**：改 `~/.config/nvim/init.lua` **就是**在改 repo 裡的檔案，`git status` 會直接看到。不需要「複製回 repo」這個步驟。
- `nvim/init.lua` 是唯一的 nvim 設定，沒有拆模組。開頭的 `gg_*` 函式是 gitgraph 的預覽節點功能（把未提交變更／stash 轉成臨時 commit 讓 gitgraph 畫出來）。
- `nvim/lazy-lock.json` **納入版控**，外掛版本靠它鎖定還原。

## 陷阱

- **tmux 必須是 `~/.local/bin/tmux`**（版本鎖定、原始碼編譯）。apt 的 3.2a 會噴 `allow-passthrough: invalid option`。若 `/usr/local/bin/tmux` 存在會搶先被找到，要清掉。
- **終端機面板單一顯示原則**：清理其他終端機時必須用 `vim.api.nvim_win_close()`，不能用 `t:close()`。
- **開關終端機後要呼叫 `force_edgy_relayout()`**：claude 這類自繪 TUI 不一定收得到 resize 通知，單純 `redraw!` 沒用。
- **Esc 延遲有兩層**：tmux 的 `escape-time` 和 nvim 的 `ttimeoutlen`，兩個都要設才有效。
- **git remote 因主機而異**，接手時先跑 `git remote -v` 確認是 SSH 還是 HTTPS。

## 禁止

- 不要把密鑰放進 `claude/mcp-servers.json`，這個 repo 會推上 GitHub。實際的值放 `~/.config/claude-secrets.env`。

詳細脈絡、待辦與踩過的坑見 `~/HANDOFF.md`。

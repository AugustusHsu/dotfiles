# dotfiles

個人開發環境設定，涵蓋 Ghostty、tmux、Neovim、GNOME 快捷鍵，目標是能在新機器上快速重建一致的工作環境。

## 目錄結構

| 路徑 | 內容 |
|---|---|
| `ghostty/config.ghostty` | 字體、主題、視窗留白、游標樣式 |
| `tmux/tmux.conf` | Shift+Enter 相容設定、狀態列提示、Ctrl+hjkl 導航綁定 |
| `nvim/init.lua` | Neovim 設定（lazy.nvim + neo-tree + vim-tmux-navigator + catppuccin） |
| `nvim/lazy-lock.json` | Neovim 外掛版本鎖定檔，見下方「更新外掛」 |
| `bash/ide.sh` | `ide()` 函式，依目錄自動建立/接回 tmux session |
| `gnome/keybindings.sh` | GNOME 工作區切換快捷鍵設定 |
| `install.sh` | 安裝腳本，見下方「安裝」 |

## 安裝

```bash
git clone <此 repo 網址> ~/code/dotfiles
bash ~/code/dotfiles/install.sh
```

`install.sh` 會做的事：

1. 檢查 apt 相依套件（`ghostty`、`tmux`、`tree`、`git`、`curl`）是否已安裝，缺少會列出 `sudo apt install` 指令並中止
2. 安裝 `JetBrainsMono Nerd Font`（鎖定版本，供 neo-tree 圖示用）
3. 安裝 `Neovim`（鎖定版本，官方 AppImage 裝到 `~/.local/bin`，不走 apt——apt 只有過舊的 0.9.5）
4. 把設定檔 symlink 到對應位置（`~/.config/ghostty`、`~/.tmux.conf`、`~/.config/nvim`）
5. 在 `~/.bashrc` 加入 `ide()` 函式的載入
6. 套用 GNOME 工作區快捷鍵設定
7. 依 `lazy-lock.json` 還原 Neovim 外掛到鎖定的版本

版本全部鎖定（`install.sh` 頂端的 `NVIM_VERSION` / `NERD_FONT_VERSION` + `lazy-lock.json`），確保每台機器裝到一致的版本。

> `sudo apt install` 需要互動輸入密碼，若在沒有 TTY 的環境（例如透過 Claude Code 執行）會失敗，需自行在終端機手動執行。

## `ide` 指令

在任一專案目錄下執行 `ide`，會建立（或接回）一個以目錄名稱命名的 tmux session：

```
┌─────────────────────────────────┐
│  nvim .（約 70% 高）             │
│  neo-tree 側邊欄 + 編輯區        │
├─────────────────────────────────┤
│  claude（約 30% 高）             │
└─────────────────────────────────┘
```

同一目錄重複執行會接回既有 session（Claude 對話與編輯狀態都會保留）。

### 導航快捷鍵（跨 nvim 視窗與 tmux pane）

`vim-tmux-navigator` 把 nvim 視窗與 tmux pane 縫成同一套，用一組 `Ctrl+hjkl` 即可在側邊欄、編輯器、claude pane 之間移動：

| 按鍵 | 動作 |
|---|---|
| `Ctrl+h/j/k/l` | 移到左/下/上/右的視窗或 pane |
| `C-b z` | 縮放目前 pane |
| `C-b Q` | 關閉整個 ide（會跳確認） |
| `C-b d` | Detach（session 留在背景） |

> 副作用：`Ctrl+l` 在 claude/shell pane 會變成「往右切」而非「清畫面」（統一導航攔了全域 Ctrl+l）。

### neo-tree 側邊欄

側邊欄頂端有圖示分頁切換器（等同 VSCode 的 activity bar）：

| 按鍵 | 動作 |
|---|---|
| `<leader>e` | 側邊欄開關（leader = 空白鍵） |
| `<leader>1` / `2` / `3` | 切到 `󰙅 Files` / `󰊢 Git` / `󰈔 Buffers` |
| `<` / `>` | 在側邊欄內循環上一個/下一個 source |

側邊欄內常用：`Enter`/`o` 開檔、`a`/`d`/`r` 新增/刪除/改名、`H` 顯示隱藏檔、`R` 重新整理、`?` 完整按鍵說明。
Git 分頁專屬：`ga` 暫存、`gu` 取消暫存、`gc` commit、`gp` push、`gg` commit+push。

## Neovim 版本與外掛

- **Neovim 用官方 AppImage 裝在 `~/.local/bin/nvim`**（版本鎖定於 `install.sh` 的 `NVIM_VERSION`）。apt 的 0.9.5 太舊、新外掛常要求 0.10+，故不走 apt。要還原成 apt 版，刪掉 `~/.local/bin/nvim` 與 `nvim.appimage` 即可。
- 外掛用 [lazy.nvim](https://github.com/folke/lazy.nvim) 管理，設定在 `nvim/init.lua`：
  - `catppuccin/nvim`（mocha，跟 Ghostty 主題一致）
  - `neo-tree.nvim`（檔案樹 + git_status + buffers 三個可切換 source）＋依賴 `plenary.nvim`、`nui.nvim`
  - `vim-tmux-navigator`（統一 Ctrl+hjkl 導航）
  - `nvim-web-devicons`（圖示）

**`nvim/lazy-lock.json`** 記錄每個外掛鎖定的確切 commit，納入版本控制以確保各機器外掛版本一致。

**要更新外掛版本時：**

1. 在 nvim 裡執行 `:Lazy update`，外掛更新到最新版，`lazy-lock.json` 會自動改寫
2. 確認沒問題後，把 `lazy-lock.json` 的異動 commit 進這個 repo
3. 其他機器跑 `install.sh`（或 nvim 內 `:Lazy restore`）就會同步到這個版本

換新機器若只想跟目前版本一致（而非裝最新），直接跑 `install.sh` 即可（內部呼叫 `require('lazy').restore()`）。

## GNOME 快捷鍵

`gnome/keybindings.sh` 把工作區切換快捷鍵從預設的 `Ctrl+Alt+方向鍵` 改成 `Ctrl+Super+方向鍵`，讓 `Ctrl+Alt+方向鍵` 空出來給 Ghostty 切換分割視窗使用（兩者原本會衝突）。

## Git commit 慣例

Commit message 格式參考 `my_workstation` 專案的慣例：

```
<gitmoji> <type>(<scope>): <繁體中文標題>

- 條列式說明變更內容
```

常用對照：`feat` ✨、`fix` 🐛、`docs` 📝、`refactor` ♻️、`chore` 🔧、`test` ✅。

# dotfiles

個人開發環境設定，涵蓋 Ghostty、tmux、Neovim、GNOME 快捷鍵，目標是能在新機器上快速重建一致的工作環境。

## 目錄結構

| 路徑 | 內容 |
|---|---|
| `ghostty/config.ghostty` | 字體、主題、視窗留白、游標樣式 |
| `tmux/tmux.conf` | Shift+Enter 相容設定、狀態列快捷鍵提示、`ide()` 版面用到的按鍵綁定 |
| `nvim/init.lua` | Neovim 設定（lazy.nvim + nvim-tree + catppuccin） |
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

1. 檢查必要套件（`ghostty`、`tmux`、`tree`、`git`、`nvim`、`curl`）是否已安裝，缺少會列出對應的 `sudo apt install` 指令並中止，需要手動安裝後重跑
2. 安裝 `JetBrainsMono Nerd Font Mono`（若尚未安裝），供 nvim-tree 圖示使用
3. 把設定檔 symlink 到對應位置（`~/.config/ghostty`、`~/.tmux.conf`、`~/.config/nvim`）
4. 在 `~/.bashrc` 加入 `ide()` 函式的載入
5. 套用 GNOME 工作區快捷鍵設定
6. 依 `lazy-lock.json` 還原 Neovim 外掛到鎖定的版本

> `sudo apt install` 需要互動輸入密碼，若在沒有 TTY 的環境（例如透過 Claude Code 執行）會失敗，需自行在終端機手動執行。

## `ide` 指令

在任一專案目錄下執行 `ide`，會建立（或接回）一個以目錄名稱命名的 tmux session：

```
┌─────────────────────────────────┐
│  nvim .（約 70% 高）             │
│  nvim-tree 側邊欄 + 編輯區       │
├─────────────────────────────────┤
│  claude（約 30% 高）             │
└─────────────────────────────────┘
```

同一目錄重複執行會接回既有 session（Claude 對話與編輯狀態都會保留）。

### 快捷鍵

狀態列（畫面最下面）會常駐提示：

| 按鍵 | 動作 |
|---|---|
| `C-b` + 方向鍵 / `hjkl` | 切換 pane |
| `C-b z` | 縮放目前 pane |
| `C-b Q` | 關閉整個 ide（會跳確認） |
| `C-b d` | Detach（session 留在背景） |

nvim-tree 內：`Enter`/`o` 開啟檔案、`a`/`d`/`r` 新增/刪除/重新命名。根目錄路徑標籤那一行按開啟鍵不會誤觸跳到上一層（已特別處理）。

## Neovim 外掛與更新

外掛用 [lazy.nvim](https://github.com/folke/lazy.nvim) 管理，設定在 `nvim/init.lua`：

- `catppuccin/nvim`（mocha 版本，跟 Ghostty 主題一致）
- `nvim-tree.lua`（釘選 `compat-nvim-0.9` tag，因本機 Neovim 版本為 0.9.5，最新版 nvim-tree 需要 0.10+）
- `nvim-web-devicons`（圖示）

**`nvim/lazy-lock.json`** 記錄每個外掛目前鎖定的確切 commit，納入版本控制是為了讓不同機器裝到完全一樣的外掛版本，避免某台機器因為外掛更新而行為跟其他機器不一致。

**要更新外掛版本時：**

1. 在 nvim 裡執行 `:Lazy update`，外掛會更新到最新版，`lazy-lock.json` 也會被自動改寫
2. 確認更新後沒有問題，把 `lazy-lock.json` 的異動 commit 進這個 repo
3. 其他機器之後跑 `install.sh`（或手動在 nvim 執行 `:Lazy restore`）就會同步拿到這個新版本

如果只是換一台新機器、想跟目前這台機器的外掛版本完全一致（而不是裝最新版），直接跑 `install.sh` 就會自動處理（內部呼叫 `require('lazy').restore()`），不用手動執行 `:Lazy update`。

## GNOME 快捷鍵

`gnome/keybindings.sh` 把工作區切換快捷鍵從預設的 `Ctrl+Alt+方向鍵` 改成 `Ctrl+Super+方向鍵`，讓 `Ctrl+Alt+方向鍵` 空出來給 Ghostty 切換分割視窗使用（兩者原本會衝突）。

## Git commit 慣例

Commit message 格式參考 `my_workstation` 專案的慣例：

```
<gitmoji> <type>(<scope>): <繁體中文標題>

- 條列式說明變更內容
```

常用對照：`feat` ✨、`fix` 🐛、`docs` 📝、`refactor` ♻️、`chore` 🔧、`test` ✅。

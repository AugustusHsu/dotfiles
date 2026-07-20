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
git clone https://github.com/AugustusHsu/dotfiles.git ~/code/dotfiles
bash ~/code/dotfiles/install.sh
```

`install.sh` 會做的事：

1. 檢查相依套件是否已安裝，缺少會列出安裝指令並中止：
   - `ghostty`——**不在 apt 套件庫，是 snap 套件**，提示的指令是 `sudo snap install ghostty --classic`
   - apt 套件：`git`、`curl`、`xz-utils`、`fontconfig`、`bison`、`build-essential`、`pkg-config`、`libevent-dev`、`libncurses-dev`
2. 安裝 `JetBrainsMono Nerd Font`（鎖定版本，供 neo-tree 圖示用）
3. 安裝 `Neovim`（鎖定版本，官方 AppImage 裝到 `~/.local/bin`，不走 apt——apt 只有過舊的 0.9.5）
4. 安裝 `tmux`（鎖定版本，原始碼編譯裝到 `~/.local/bin`，不走 apt——Ubuntu 22.04 apt 只有 3.2a，缺 `allow-passthrough` 等新選項）
5. 把設定檔 symlink 到對應位置（`~/.config/ghostty`、`~/.tmux.conf`、`~/.config/nvim`）
6. 在 `~/.bashrc` 加入 `ide()` 函式的載入
7. 套用 GNOME 工作區快捷鍵設定
8. 依 `lazy-lock.json` 還原 Neovim 外掛到鎖定的版本

版本全部鎖定（`install.sh` 頂端的 `NVIM_VERSION` / `NERD_FONT_VERSION` / `TMUX_VERSION` + `lazy-lock.json`），確保每台機器裝到一致的版本。

> repo 路徑由 `install.sh` 從自己的位置推導，clone 到 `~/code/dotfiles` 以外的地方也能正常運作。
>
> 若目標位置已經有同名的設定檔（例如既有的 `~/.tmux.conf`）：repo 裡還沒收錄這份設定時會把它搬進 repo 納入版控；repo 裡已經有了則**不會覆蓋 repo 版本**，而是把機器上的原檔備份成 `.bak` 再建立 symlink。

> tmux 是 client/server 架構：升級後如果背景還有舊版啟動的 server 在跑，client 版本號會顯示新的，但實際設定跟功能還是舊 server 的。若遇到新設定選項噴 `invalid option`，先確認是不是要 `tmux kill-server` 重啟 server（會清空所有現有 session，記得先保留要留的工作）。

> `sudo apt install` 需要互動輸入密碼，若在沒有 TTY 的環境（例如透過 Claude Code 執行）會失敗，需自行在終端機手動執行。

## `ide` 指令

在任一專案目錄下執行 `ide`，會建立（或接回）一個以目錄名稱命名的 tmux session，裡面單一 `nvim .` 全螢幕——IDE 的所有面板（檔案樹、編輯器、git、底部終端機）都在 nvim 內部：

```
┌──────────┬─────────────────────────────┐
│ neo-tree │  bufferline 頂端分頁         │
│ 側邊欄   │  編輯器                      │
│ (左,全高)├─────────────────────────────┤
│          │  toggleterm 底部終端機         │
└──────────┴─────────────────────────────┘
```

同一目錄重複執行會接回既有 session（Claude 對話與編輯狀態都會保留）。

### 導航快捷鍵（跨 nvim 視窗與 tmux pane）

`vim-tmux-navigator` 把 nvim 視窗與 tmux pane 縫成同一套，用一組 `Ctrl+hjkl` 即可在側邊欄、編輯器、底部終端機之間移動：

| 按鍵 | 動作 |
|---|---|
| `Ctrl+h/j/k/l` | 移到左/下/上/右的視窗或 pane |
| `C-b z` | 縮放目前 pane（`ide` 預設只有單一 pane 塞滿整個 nvim，這個鍵沒有視覺效果；只有你自己手動 `C-b %`/`C-b "` 開額外 pane 時才有用） |
| `C-b Q` | 關閉整個 ide（會跳確認） |
| `C-b d` | Detach（session 留在背景） |

tmux 狀態列（畫面最下面那一條）常駐顯示 `Ctrl+hjkl` 移動、`Q` 關閉、`d` 離開，以及底部終端機面板的 `C-/`（開關）、`C-t`（清單）；`C-b z` 因為預設情境下沒有視覺效果，不放進提示列。

> 副作用：`Ctrl+l` 在 claude/shell pane 會變成「往右切」而非「清畫面」（統一導航攔了全域 Ctrl+l）。

在底部終端機（見下方）裡，`Ctrl+hjkl` 會先跳出終端機的 insert 模式、再移到對應視窗，不用先按 `Esc`。

### neo-tree 側邊欄

側邊欄頂端有圖示分頁切換器（等同 VSCode 的 activity bar）：

| 按鍵 | 動作 |
|---|---|
| `<leader>e` | 側邊欄開關（leader = 空白鍵） |
| `<leader>1` / `2` | 切到 `󰙅 Files` / `󰊢 Git` |
| `<` / `>` | 在側邊欄內循環上一個/下一個 source |

（開啟的檔案改由頂端 bufferline 呈現，故側邊欄不再有 Buffers source。）

側邊欄內常用：`Enter`/`o` 開檔、`a`/`d`/`r` 新增/刪除/改名、`H` 顯示隱藏檔、`R` 重新整理、`?` 完整按鍵說明。
Git 分頁（`<leader>2`）專屬：`ga` 暫存、`gu` 取消暫存、`gc` commit、`gp` push、`gg` commit+push。

### Git 功能快捷鍵

除了側邊欄的 Git 分頁（變更檔案清單 + 暫存/提交），另有這些 git 工具：

| 按鍵 | 動作 | 來源 |
|---|---|---|
| `]c` / `[c` | 跳到下/上一個變更區塊（hunk） | gitsigns |
| `<leader>gp` | 預覽游標所在 hunk | gitsigns |
| `<leader>gs` | 暫存游標所在 hunk | gitsigns |
| `<leader>gr` | 還原游標所在 hunk | gitsigns |
| `<leader>gb` | 切換行內 blame | gitsigns |
| `<leader>gd` | 開 Diffview 看目前所有變更 | diffview |
| `<leader>gh` | 目前檔案的 commit 歷史 | diffview |
| `<leader>gg` | 開提交樹狀圖（gitgraph） | gitgraph |

編輯器左側 gutter 會即時顯示哪幾行新增/修改/刪除（gitsigns，自動開啟）。

**gitgraph 圖內按鍵**（buffer-local，只在圖裡有效）：

| 按鍵 | 動作 |
|---|---|
| `Enter` | 看游標所在 commit 的 diff（開 diffview） |
| `<leader>gm` | 顯示該 commit 的完整 message（浮窗，`q`/`Esc` 關） |
| `<leader>co` | checkout 該 commit（detached HEAD，先確認） |
| `<leader>cb` | checkout 該 commit 的分支 |
| `q` | 返回編輯器 |

**退出**：diffview 在畫面內按 `q`（或 `:DiffviewClose`）；gitgraph 按 `q` 返回編輯器。

**未提交的變更 / stash 預覽節點**：圖裡除了真正的 commit，還會多畫出兩種虛擬節點，跟真正的 commit 用不同符號和顏色區分：

| 符號 | 顏色 | 代表 |
|---|---|---|
| `●` | 黃色 | 目前尚未 commit 的變更（staged + unstaged + untracked），永遠排在最上面／主線，訊息顯示變更的檔案數，例如「未提交的變更 (2)」 |
| `◆` | 紫色 | stash 清單裡的每一筆，正確掛在它當初是從哪個 commit 建立的位置上，訊息格式「`stash: WIP on <分支>: <訊息> <hash> <時間>`」（訊息超過 24 字元會截斷加 `...`） |

這兩種節點都能用 `Enter` 看 diff，跟真正的 commit 操作一致；`<leader>co`/`<leader>cb`/`<leader>gm` 則只對真正的 commit 有意義。開圖跟關圖（`q`）之間會自動同步/清理狀態，不用手動處理。

### 頂端 buffer 分頁（bufferline）

開啟的檔案會排成頂端分頁（像 VSCode 的編輯器分頁），會自動幫 neo-tree 側邊欄留位不重疊：

| 按鍵 | 動作 |
|---|---|
| `]b` / `[b` | 下一個 / 上一個分頁 |
| `<leader>bp` | 選取分頁（每個分頁顯示字母，按字母跳） |
| `<leader>bd` | 關閉目前 buffer |
| `<leader>bo` | 關閉其他 buffer |

### 底部終端機面板（toggleterm）

編輯器下方有一個底部終端機面板（由 edgy 釘住），**畫面上永遠只顯示一個終端機**（單一面板原則，開新的/切換都會自動隱藏其他已開的）：

| 按鍵 | 動作 |
|---|---|
| `Ctrl+/` 或 `Ctrl+_` | 開關終端機面板（n / t / i 模式都能按） |

`Ctrl+/` 開關的對象是**最後使用的終端機**：預設是 `claude`，但只要透過 `Ctrl+t` 切換過其他終端機，之後 `Ctrl+/` 開關的就是那個，不會強制跳回 `claude`。

終端機內按 `Ctrl+hjkl` 會跳出終端機模式並移到對應視窗（見上方導航章節）；沒有目標視窗可切（例如終端機在版面最下面/最右邊，往下/往右沒東西）時會留在終端機、可以直接繼續打字，不會卡在 Normal 模式。快捷鍵提示顯示在畫面最下面的 tmux 狀態列（不佔用終端機面板自己的空間）。

### 終端機清單面板（Ctrl+t，toggleterm-manager）

`Ctrl+t` 開啟一個 telescope 面板，列出所有已開的終端機（右側有預覽），可以新增、切換、改名、刪除：

| 按鍵 | 動作 |
|---|---|
| `Ctrl+j` / `Ctrl+k` | 上下移動選取 |
| `Enter` | 切換到選中的終端機（隱藏其他已開的，聚焦並進 insert） |
| `Ctrl+i` | 新增終端機 |
| `Ctrl+r` | 重新命名選中的終端機 |
| `Ctrl+d` | 刪除選中的終端機 |

清單狀態欄：`a` = 顯示中、`h` = 已隱藏，前綴 `%` = 目前所在的 buffer。快捷鍵說明也直接印在面板標題上。

### 指令提示（which-key）

不用背快捷鍵——按下前綴鍵（例如 `<leader>` 空白鍵、或 `g`）稍等一下，畫面**最下面**會跳出目前情境可用的指令清單（依你所在的功能顯示，`<leader>g` 開頭的歸「Git」群組、`<leader>b` 歸「Buffer」群組）。

## Neovim 版本與外掛

- **Neovim 用官方 AppImage 裝在 `~/.local/bin/nvim`**（版本鎖定於 `install.sh` 的 `NVIM_VERSION`）。apt 的 0.9.5 太舊、新外掛常要求 0.10+，故不走 apt。要還原成 apt 版，刪掉 `~/.local/bin/nvim` 與 `nvim.appimage` 即可。
- 外掛用 [lazy.nvim](https://github.com/folke/lazy.nvim) 管理，設定在 `nvim/init.lua`：
  - `catppuccin/nvim`（mocha，跟 Ghostty 主題一致）
  - `neo-tree.nvim`（檔案樹 + git_status 兩個可切換 source）＋依賴 `plenary.nvim`、`nui.nvim`
  - `vim-tmux-navigator`（統一 Ctrl+hjkl 導航）
  - `gitsigns.nvim`（gutter 標記、hunk 暫存、行內 blame）
  - `diffview.nvim`（diff / 檔案歷史 / 衝突解決）
  - `gitgraph.nvim`（提交樹狀圖）
  - `which-key.nvim`（按前綴鍵時在畫面最下面提示可用指令）
  - `bufferline.nvim`（頂端 VSCode 式的 buffer 分頁）
  - `toggleterm.nvim`（底部終端機面板，預設起 claude）
  - `edgy.nvim`（版面管理：neo-tree 釘左、toggleterm 釘底）
  - `telescope.nvim`（模糊搜尋框架，供終端機清單面板使用）＋依賴 `plenary.nvim`
  - `toggleterm-manager.nvim`（`Ctrl+t` 終端機清單面板：切換/新增/改名/刪除）
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

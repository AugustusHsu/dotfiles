-- bootstrap lazy.nvim
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({
    "git", "clone", "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable",
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

-- 停用 netrw：改由 neo-tree 完全處理目錄，避免 `nvim .` 時 netrw 搶先顯示在編輯器
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

vim.g.mapleader = " "

-- 強制 edgy 重新計算版面寬高並整個重繪：edgy 只在「自己」偵測到的
-- WinClosed/show/hide 時才會自動 require("edgy.layout").update()；
-- 我們自己開關/切換終端機（claude:toggle()、toggleterm-manager 的
-- 切換 action）不一定會經過那個路徑，導致 edgy 算出來的寬度沒更新、
-- 編輯器或旁邊視窗畫面卡住要重開才會恢復。這些操作後手動補一次。
--
-- 光 redraw! 只會重畫 nvim 這邊「以為」的畫面，不會通知底層 pty/job
-- 真正的尺寸已經變了。像 claude 這種自己畫 TUI 的 CLI，如果視窗在它
-- 畫面畫出來之後才被 edgy 調整大小，它不一定會收到 resize 通知去重畫，
-- 畫面就會卡在舊尺寸、留下一塊沒畫到的空白/黑色區域。這裡額外主動呼叫
-- jobresize 用視窗「目前的實際大小」逼一次真正的 resize 通知。
local function force_edgy_relayout()
  vim.schedule(function()
    pcall(function()
      require("edgy.layout").update()
    end)
    vim.cmd("redraw!")
    local ok, terms = pcall(function()
      return require("toggleterm.terminal").get_all(true)
    end)
    if ok then
      for _, term in ipairs(terms) do
        if term.job_id and term.window and vim.api.nvim_win_is_valid(term.window) then
          local width = vim.api.nvim_win_get_width(term.window)
          local height = vim.api.nvim_win_get_height(term.window)
          pcall(vim.fn.jobresize, term.job_id, width, height)
        end
      end
    end
  end)
end

-- Ctrl+/ 開關的目標：預設是 claude，但只要透過 Ctrl+t 切換過其他終端機，
-- 就記住那個「最後使用的終端機」，之後 Ctrl+/ 開關的對象改成它，而不是
-- 永遠強制跳回 claude。等 toggleterm 的 config 跑過才會被賦值成 claude。
local last_terminal = nil

-- Alt+Z 縮放終端機面板：開一個蓋滿整個畫面的浮動視窗顯示終端機 buffer，
-- 不是 nil 就代表目前處於「放大」狀態。用浮動視窗而不是直接關掉編輯器/
-- 側邊欄視窗，是因為 edgy 對「main 區域視窗全部消失、只剩邊欄視窗」有
-- 自己的保護機制，一偵測到就會反過來把邊欄（含終端機）也關掉、生一個
-- 空 buffer 收拾殘局——實測會直接把終端機關掉、卡住恢復不了。浮動視窗
-- 完全不動 edgy 管理的版面，底下真正的終端機視窗全程都在，只是被蓋住。
local zoom_float_win = nil

-- 開關/切換/新增終端機（C-/、toggleterm-manager 的切換/新增）都要呼叫
-- 這個，確保縮放狀態不會殘留到下一個顯示出來的終端機上。
local function close_terminal_zoom()
  if zoom_float_win and vim.api.nvim_win_is_valid(zoom_float_win) then
    vim.api.nvim_win_close(zoom_float_win, false)
  end
  zoom_float_win = nil
end

-- gitgraph 圖裡顯示「尚未 commit 的變更」跟「全部 stash」用的臨時 ref 命名空間。
-- 放在 refs/heads、refs/tags 之外的自訂命名空間，git branch/git tag 都看不到，
-- 但 git log --all 還是抓得到（--all 涵蓋 refs/ 底下所有 ref，不限 heads/tags）。
local GG_PREVIEW_REF_PREFIX = "refs/gitgraph-preview/"

-- gitgraph 原本用 all = true（等於 git log --all）畫圖，但 --all 涵蓋
-- refs/ 底下「所有」ref，包含 refs/stash 本身——這樣真正的 stash 跟它的
-- index commit 還是會被畫出來，跟我們自己建立的乾淨版本重複顯示。改成明確
-- 列出 --branches --tags --remotes（--all 原本涵蓋的主要範圍）加上我們自己
-- 的臨時 ref 命名空間，藉此排除 refs/stash。
local GG_REVISION_RANGE = "--branches --tags --remotes --glob='" .. GG_PREVIEW_REF_PREFIX .. "*'"

-- 這次同步產生的臨時 commit 短 hash（對齊 gitgraph 用 %h 顯示的格式）→ 種類
-- （"uncommitted" 或 "stash"），畫完圖後用來把這些「虛擬」節點跟真正的
-- commit 視覺上區分開來，兩種還各自用不同符號
local gg_preview_kind_by_hash = {}

-- 清掉所有我們自己建立的臨時 ref
local function gg_cleanup_preview_refs()
  local refs = vim.fn.systemlist({ "git", "for-each-ref", "--format=%(refname)", GG_PREVIEW_REF_PREFIX })
  for _, ref in ipairs(refs) do
    if ref ~= "" then
      vim.fn.system({ "git", "update-ref", "-d", ref })
    end
  end
end

-- 字數超過上限就砍斷、補上「...」。用 strchars/strcharpart（照「字元」數，
-- 不是 byte 數）避免把中文字元從中間切斷。
local GG_MSG_MAX_CHARS = 24
local function gg_truncate(s, max_chars)
  if vim.fn.strchars(s) <= max_chars then
    return s
  end
  return vim.fn.strcharpart(s, 0, max_chars) .. "..."
end

-- 把一個 tree + parent + 自訂訊息包成一個**單一 parent**的乾淨 commit。
-- 不管是「未提交的變更」還是 stash，都用這個共用函式：git stash 格式
-- 本身一定會帶一個「index on ...」的額外 commit（用來還原 staged/unstaged
-- 的區別），這裡只是要「看」，不需要能還原，直接複用來源的 tree 內容，
-- 包成單一 parent、訊息完全自訂的乾淨版本，畫在圖上就只會佔一個節點。
--
-- date（可省略，ISO 格式）：git commit-tree 預設用「現在」當這個 commit 的
-- 時間，如果不明確指定，stash 每次重畫都會被蓋成「現在」，跟真正未提交的
-- 變更幾乎同時間，gitgraph 的 --date-order 排序、左右分支的位置就會沒有
-- 固定規則。stash 一定要傳回它原本真正建立的時間，才會穩定排在「未提交的
-- 變更」（真正的現在）下面、退到右邊的分支。
local function gg_commit_tree_from(tree, parent, message, date)
  local old_author, old_committer = vim.env.GIT_AUTHOR_DATE, vim.env.GIT_COMMITTER_DATE
  if date then
    vim.env.GIT_AUTHOR_DATE = date
    vim.env.GIT_COMMITTER_DATE = date
  end
  local commit = vim.fn.system({ "git", "commit-tree", tree, "-p", parent, "-m", message }):gsub("%s+$", "")
  vim.env.GIT_AUTHOR_DATE = old_author
  vim.env.GIT_COMMITTER_DATE = old_committer
  if vim.v.shell_error ~= 0 or commit == "" then
    return nil
  end
  return commit
end

-- 「尚未 commit 的變更」快照：借一個暫時的 index 檔案（GIT_INDEX_FILE，
-- 不會動到真正的 git 狀態/工作區，用完就丟）把目前 staged+unstaged+
-- untracked 的變更寫成一個 tree，訊息裡帶上變更的檔案數量。
-- 沒有任何變更時回傳 nil（tree 會跟 HEAD 一樣，判斷到就跳過）。
local function gg_snapshot_uncommitted()
  local old_index = vim.env.GIT_INDEX_FILE
  local tmp_index = vim.fn.tempname()
  vim.env.GIT_INDEX_FILE = tmp_index
  vim.fn.system({ "git", "read-tree", "HEAD" })
  vim.fn.system({ "git", "add", "-A" })
  local tree = vim.fn.system({ "git", "write-tree" }):gsub("%s+$", "")
  vim.env.GIT_INDEX_FILE = old_index
  pcall(os.remove, tmp_index)
  if vim.v.shell_error ~= 0 or tree == "" then
    return nil
  end

  local head = vim.fn.system({ "git", "rev-parse", "HEAD" }):gsub("%s+$", "")
  local head_tree = vim.fn.system({ "git", "rev-parse", "HEAD^{tree}" }):gsub("%s+$", "")
  if tree == head_tree then
    return nil -- 沒有任何變更
  end

  local files = vim.fn.systemlist({ "git", "diff", "--name-only", head, tree })
  local msg = ("未提交的變更 (%d)"):format(#files)
  return gg_commit_tree_from(tree, head, msg)
end

-- 把一筆 stash 轉成乾淨的單一 parent commit：stash 這個 commit 物件自己的
-- tree 就已經是完整的變更內容了（不用另外組），直接複用它 + 它原本的第一個
-- parent，訊息改成自訂格式「stash: WIP on <branch>: <訊息> <短 hash> <時間>」。
local function gg_snapshot_stash(stash_ref)
  local tree = vim.fn.system({ "git", "rev-parse", stash_ref .. "^{tree}" }):gsub("%s+$", "")
  local parent = vim.fn.system({ "git", "rev-parse", stash_ref .. "^1" }):gsub("%s+$", "")
  if vim.v.shell_error ~= 0 or tree == "" or parent == "" then
    return nil
  end

  local orig_msg = vim.fn.system({ "git", "log", "-1", "--format=%s", stash_ref }):gsub("%s+$", "")
  -- git 自動組的訊息有兩種格式：沒給 -m 是「WIP on <branch>: <hash> <subject>」，
  -- 有給 -m 是「On <branch>: <message>」，兩種都要處理。冒號後面那段（不管
  -- 是使用者自己給的 -m 訊息，還是沒給時 git 自動帶的 hash+subject）當作
  -- 「訊息」塞進我們自己的格式裡，太長就截斷。
  local branch, tail = orig_msg:match("^%a+ on ([^:]+):%s*(.*)$")
  if not branch then
    branch, tail = orig_msg:match("^On ([^:]+):%s*(.*)$")
  end
  branch = branch or "?"
  local stash_msg = gg_truncate(tail or "", GG_MSG_MAX_CHARS)
  local short = vim.fn.system({ "git", "rev-parse", "--short", stash_ref }):gsub("%s+$", "")
  local display_date = vim.fn
    .system({ "git", "log", "-1", "--format=%ad", "--date=format:%Y-%m-%d %H:%M", stash_ref })
    :gsub("%s+$", "")
  -- 傳給 commit-tree 用的日期要跟 stash 原本真正的時間一致（見
  -- gg_commit_tree_from 的說明），跟訊息裡顯示用的日期分開拿一次、格式不同
  local commit_date = vim.fn.system({ "git", "log", "-1", "--format=%aI", stash_ref }):gsub("%s+$", "")
  local msg = ("stash: WIP on %s: %s %s %s"):format(branch, stash_msg, short, display_date)
  return gg_commit_tree_from(tree, parent, msg, commit_date)
end

-- 建立/更新臨時 ref，讓 gitgraph 的 git log --all 天生就能把這些畫進圖裡，
-- 掛在正確的 commit 上，不用改 gitgraph.nvim 半行程式碼：
--
-- 1. 「尚未 commit 的變更」：見 gg_snapshot_uncommitted()。
-- 2. 「全部 stash」：refs/stash 只會指到最新一筆（stash@{0}），更舊的
--    只存在 reflog，--all 抓不到，所以逐一列出 git stash list 幫每一筆
--    自己補一個臨時 ref（都先轉成 gg_snapshot_stash() 的乾淨版本）。
local function gg_sync_preview_refs()
  gg_cleanup_preview_refs()
  gg_preview_kind_by_hash = {}

  local function remember_short_hash(full_hash, kind)
    local short = vim.fn.system({ "git", "rev-parse", "--short", full_hash }):gsub("%s+$", "")
    if short ~= "" then
      gg_preview_kind_by_hash[short] = kind
    end
  end

  local uncommitted = gg_snapshot_uncommitted()
  if uncommitted then
    vim.fn.system({ "git", "update-ref", GG_PREVIEW_REF_PREFIX .. "uncommitted", uncommitted })
    remember_short_hash(uncommitted, "uncommitted")
  end

  local stash_refs = vim.fn.systemlist({ "git", "stash", "list", "--format=%H" })
  for i, stash_hash in ipairs(stash_refs) do
    if stash_hash ~= "" then
      local clean = gg_snapshot_stash(stash_hash)
      if clean then
        vim.fn.system({ "git", "update-ref", GG_PREVIEW_REF_PREFIX .. "stash-" .. (i - 1), clean })
        remember_short_hash(clean, "stash")
      end
    end
  end
end

-- 「未提交的變更」/「stash」節點跟真正的 commit 長得太像，容易搞混。
-- 畫完圖之後幫這些節點：
-- 1. 打上顏色，跟真正的 commit 明顯不同——未提交的變更用黃色、stash 用
--    紫色，兩種虛擬節點彼此也分得出來
-- 2. 把 hash/日期/作者那行從「hash 開始」的部分截掉，只留左邊的分支符號
--    ——gitgraph 的欄位順序、要不要顯示 hash/日期是全域設定（format.fields），
--    沒辦法只針對這幾個節點單獨關掉，只能用「截字」的方式讓它視覺上只剩一行
--    有內容，游標對應 commit 的邏輯不受影響（改的是畫面文字，不是 graph 資料）
-- 3. 把節點符號本身也換掉（未提交的變更用 ●、stash 用 ◆），不只是變色，
--    連符號都跟真正的 commit（*）不一樣。symbols 設定（config.symbols）
--    是全域的，沒辦法只對這幾個節點單獨換符號，所以一樣用改畫面文字的方式
local GG_HL_PLUMBING = "GitGraphPlumbingNode"
local GG_HL_NS = vim.api.nvim_create_namespace("gitgraph_preview")
local GG_PREVIEW_ICON = { uncommitted = "●", stash = "◆" }
local GG_PREVIEW_HL = { uncommitted = "GitGraphUncommittedNode", stash = "GitGraphStashNode" }
vim.api.nvim_set_hl(0, GG_PREVIEW_HL.uncommitted, { fg = "#f9e2af", bold = true, default = true }) -- 黃
vim.api.nvim_set_hl(0, GG_PREVIEW_HL.stash, { fg = "#cba6f7", bold = true, default = true }) -- 紫
vim.api.nvim_set_hl(0, GG_HL_PLUMBING, { fg = "#6c7086", italic = true, default = true })

local function gg_style_preview_nodes()
  local ok, draw = pcall(require, "gitgraph.draw")
  if not ok or not draw.graph then
    return
  end
  local buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_clear_namespace(buf, GG_HL_NS, 0, -1)

  local was_modifiable = vim.bo[buf].modifiable
  vim.bo[buf].modifiable = true

  for i, row in ipairs(draw.graph) do
    local commit = row.commit
    if commit then
      local hl
      local kind = gg_preview_kind_by_hash[commit.hash]
      if kind then
        hl = GG_PREVIEW_HL[kind]
        local line = vim.api.nvim_buf_get_lines(buf, i - 1, i, false)[1] or ""
        local star_col = line:find("*", 1, true)
        if star_col then
          vim.api.nvim_buf_set_text(buf, i - 1, star_col - 1, i - 1, star_col, { GG_PREVIEW_ICON[kind] or "●" })
        end
        line = vim.api.nvim_buf_get_lines(buf, i - 1, i, false)[1] or ""
        local col = line:find(commit.hash, 1, true)
        if col then
          vim.api.nvim_buf_set_text(buf, i - 1, col - 1, i - 1, #line, {})
        end
      elseif commit.msg and commit.msg:match("^index on ") then
        hl = GG_HL_PLUMBING
      end
      if hl then
        -- 每個 commit 佔兩行（hash/日期/作者那行 + 訊息那行），兩行都要上色
        for _, line_idx in ipairs({ i, i + 1 }) do
          if draw.graph[line_idx] then
            vim.api.nvim_buf_set_extmark(buf, GG_HL_NS, line_idx - 1, 0, {
              end_row = line_idx,
              hl_group = hl,
              hl_eol = true,
              priority = 5000,
            })
          end
        end
      end
    end
  end

  vim.bo[buf].modifiable = was_modifiable
end

require("lazy").setup({
  {
    "catppuccin/nvim",
    name = "catppuccin",
    priority = 1000,
    config = function()
      require("catppuccin").setup({ flavour = "mocha" })
      vim.cmd.colorscheme("catppuccin")
    end,
  },
  {
    "nvim-tree/nvim-web-devicons",
    opts = {},
  },
  {
    -- 統一 Ctrl+hjkl 導航（normal 模式）：跨 nvim 視窗與 tmux pane
    "christoomey/vim-tmux-navigator",
    lazy = false,
    init = function()
      -- 停用外掛預設綁定，改由我們自己綁；避免它在終端機模式誤觸、把指令名稱當文字送進終端機
      vim.g.tmux_navigator_no_mappings = 1
    end,
    config = function()
      vim.keymap.set("n", "<C-h>", "<cmd>TmuxNavigateLeft<cr>", { desc = "移到左邊視窗/pane", silent = true })
      vim.keymap.set("n", "<C-j>", "<cmd>TmuxNavigateDown<cr>", { desc = "移到下面視窗/pane", silent = true })
      vim.keymap.set("n", "<C-k>", "<cmd>TmuxNavigateUp<cr>", { desc = "移到上面視窗/pane", silent = true })
      vim.keymap.set("n", "<C-l>", "<cmd>TmuxNavigateRight<cr>", { desc = "移到右邊視窗/pane", silent = true })
    end,
  },
  {
    "nvim-neo-tree/neo-tree.nvim",
    branch = "v3.x",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-tree/nvim-web-devicons",
      "MunifTanjim/nui.nvim",
    },
    config = function()
      require("neo-tree").setup({
        close_if_last_window = true,
        -- buffers source 已由頂端 bufferline 取代，故移除
        sources = { "filesystem", "git_status" },
        -- 側邊欄頂端的來源切換器（圖示分頁）＝ VSCode activity bar 的角色
        source_selector = {
          winbar = true,
          content_layout = "center",
          sources = {
            { source = "filesystem", display_name = "󰙅 Files" },
            { source = "git_status", display_name = "󰊢 Git" },
          },
        },
        filesystem = {
          follow_current_file = { enabled = true },
          use_libuv_file_watcher = true,
          -- 用 `nvim .` 開資料夾時直接接管成 neo-tree 左側欄
          -- （open_default = 開在預設位置＝左側欄；不要用 open_current，那會佔滿整個視窗）
          hijack_netrw_behavior = "open_default",
          -- 預設顯示隱藏檔/目錄（neo-tree 預設會擋掉點開頭的檔案），
          -- 側邊欄內的 H 還是可以手動切回隱藏
          filtered_items = {
            hide_dotfiles = false,
          },
        },
        window = {
          position = "left",
          width = 32,
        },
      })

      -- 切換器快捷鍵（直接跳到某來源，像 VSCode Ctrl+Shift+E / G）
      vim.keymap.set("n", "<leader>e", "<cmd>Neotree toggle<cr>", { desc = "側邊欄開關", silent = true })
      vim.keymap.set("n", "<leader>1", "<cmd>Neotree filesystem<cr>", { desc = "側邊欄：Files", silent = true })
      vim.keymap.set("n", "<leader>2", "<cmd>Neotree git_status<cr>", { desc = "側邊欄：Git", silent = true })
    end,
  },
  {
    -- 編輯器 gutter 標記（+/~/_）、行內暫存 hunk、行內 blame
    "lewis6991/gitsigns.nvim",
    event = { "BufReadPre", "BufNewFile" },
    config = function()
      local gs = require("gitsigns")
      gs.setup()
      vim.keymap.set("n", "]c", function() gs.nav_hunk("next") end, { desc = "下一個 hunk" })
      vim.keymap.set("n", "[c", function() gs.nav_hunk("prev") end, { desc = "上一個 hunk" })
      vim.keymap.set("n", "<leader>gp", gs.preview_hunk, { desc = "預覽 hunk" })
      vim.keymap.set("n", "<leader>gs", gs.stage_hunk, { desc = "暫存 hunk" })
      vim.keymap.set("n", "<leader>gr", gs.reset_hunk, { desc = "還原 hunk" })
      vim.keymap.set("n", "<leader>gb", gs.toggle_current_line_blame, { desc = "切換行內 blame" })
    end,
  },
  {
    -- 看 diff、檔案歷史、合併衝突解決
    "sindrets/diffview.nvim",
    cmd = { "DiffviewOpen", "DiffviewFileHistory" },
    keys = {
      { "<leader>gd", "<cmd>DiffviewOpen<cr>", desc = "開啟 Diffview（看變更）" },
      { "<leader>gh", "<cmd>DiffviewFileHistory %<cr>", desc = "目前檔案歷史" },
    },
    config = function()
      require("diffview").setup({
        keymaps = {
          -- 在 diffview 各畫面按 q 直接關閉整個 diffview
          view = { { "n", "q", "<cmd>DiffviewClose<cr>", { desc = "關閉 Diffview" } } },
          file_panel = { { "n", "q", "<cmd>DiffviewClose<cr>", { desc = "關閉 Diffview" } } },
          file_history_panel = { { "n", "q", "<cmd>DiffviewClose<cr>", { desc = "關閉 Diffview" } } },
        },
      })
    end,
  },
  {
    -- 提交樹狀圖（分支/合併視覺化）
    "isakbm/gitgraph.nvim",
    dependencies = { "sindrets/diffview.nvim" },
    keys = {
      {
        "<leader>gg",
        -- 在編輯器視窗畫 graph（覆蓋編輯器，不開新分頁）；q 會切回覆蓋前的 buffer
        function()
          -- 若目前焦點在側邊欄，先移到右邊的編輯器，避免蓋掉 neo-tree
          if vim.bo.filetype == "neo-tree" then
            vim.cmd("wincmd l")
          end
          -- 明確記住覆蓋前的編輯器 buffer，供按 q 時精準還原
          vim.g.gitgraph_prev_buf = vim.api.nvim_get_current_buf()
          gg_sync_preview_refs()
          require("gitgraph").draw({}, { revision_range = GG_REVISION_RANGE, max_count = 5000 })
          gg_style_preview_nodes()
        end,
        desc = "Git graph（提交樹狀圖）",
      },
    },
    opts = {
      hooks = {
        -- 在 graph 上對某個 commit 按 Enter → 開 diffview 看那筆變更
        on_select_commit = function(commit)
          vim.cmd("DiffviewOpen " .. commit.hash .. "^!")
        end,
        on_select_range_commit = function(from, to)
          vim.cmd("DiffviewOpen " .. from.hash .. "~1.." .. to.hash)
        end,
      },
    },
  },
  {
    -- 按前綴鍵時在畫面最下面提示可用指令（依情境顯示，自動抓各 keymap 的 desc）
    "folke/which-key.nvim",
    event = "VeryLazy",
    config = function()
      local wk = require("which-key")
      wk.setup({})
      -- 群組標籤：讓 <leader>g / <leader>b 開頭的各自歸類
      wk.add({
        { "<leader>g", group = "Git" },
        { "<leader>b", group = "Buffer" },
        { "<leader>1", desc = "側邊欄：Files" },
        { "<leader>2", desc = "側邊欄：Git" },
        { "<leader>e", desc = "側邊欄開關" },
      })
    end,
  },
  {
    -- VSCode 式的頂端 buffer 分頁（開啟的檔案排成分頁）
    "akinsho/bufferline.nvim",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    event = "VeryLazy",
    config = function()
      require("bufferline").setup({
        options = {
          diagnostics = false,
          always_show_bufferline = true,
          show_buffer_close_icons = true,
          show_close_icon = false,
          -- 幫 neo-tree 側邊欄留位，分頁不會蓋到側邊欄
          offsets = {
            {
              filetype = "neo-tree",
              text = "檔案總管",
              text_align = "center",
              separator = true,
            },
          },
        },
        -- 未指定 highlights，bufferline 會沿用當前 colorscheme（Catppuccin）的配色
      })

      -- 關閉目前 buffer 但保留視窗：先把視窗切到別的 buffer 再刪，
      -- 避免刪掉唯一 buffer 後編輯器視窗關閉、觸發 close_if_last_window 使 nvim 退出
      local function close_current_buffer()
        local cur = vim.api.nvim_get_current_buf()
        if not vim.bo[cur].buflisted then
          vim.notify("目前不是可關閉的檔案 buffer", vim.log.levels.WARN)
          return
        end
        local alt = vim.fn.bufnr("#")
        if alt > 0 and alt ~= cur and vim.api.nvim_buf_is_valid(alt) and vim.bo[alt].buflisted then
          vim.cmd("buffer #")
        else
          local other
          for _, b in ipairs(vim.api.nvim_list_bufs()) do
            if b ~= cur and vim.bo[b].buflisted and vim.api.nvim_buf_is_valid(b) then
              other = b
              break
            end
          end
          if other then
            vim.cmd("buffer " .. other)
          else
            vim.cmd("enew") -- 沒有其他 buffer 就開一個空的，視窗才不會關
          end
        end
        pcall(vim.cmd, "bdelete " .. cur)
      end

      vim.keymap.set("n", "]b", "<cmd>BufferLineCycleNext<cr>", { desc = "下一個分頁", silent = true })
      vim.keymap.set("n", "[b", "<cmd>BufferLineCyclePrev<cr>", { desc = "上一個分頁", silent = true })
      vim.keymap.set("n", "<leader>bp", "<cmd>BufferLinePick<cr>", { desc = "選取分頁（顯示字母跳）", silent = true })
      vim.keymap.set("n", "<leader>bd", close_current_buffer, { desc = "關閉目前 buffer", silent = true })
      vim.keymap.set("n", "<leader>bo", "<cmd>BufferLineCloseOthers<cr>", { desc = "關閉其他 buffer", silent = true })
    end,
  },
  {
    -- 底部終端機面板（VSCode 式）：claude 為預設終端機
    "akinsho/toggleterm.nvim",
    event = "VeryLazy",
    config = function()
      require("toggleterm").setup({
        direction = "horizontal",
        size = 15,
        start_in_insert = true,
        terminal_mappings = true,
      })

      local Terminal = require("toggleterm.terminal").Terminal
      -- claude 預設終端機（底部水平）
      -- 不用 cmd 直接跑 claude：先開 shell，等 edgy 把面板定位到正確寬度後才啟動 claude，
      -- 避免 claude 歡迎橫幅在全寬下印出、之後被縮窄的面板切掉（且開關也修不回來）
      local claude = Terminal:new({
        direction = "horizontal",
        display_name = "claude",
        count = 1,
        on_open = function(term)
          if not term.__claude_started then
            term.__claude_started = true
            vim.defer_fn(function()
              pcall(function()
                term:send("claude")
              end)
            end, 200)
          end
        end,
      })
      last_terminal = claude -- 預設開關對象是 claude，切換過其他終端機後會改掉

      -- Ctrl+/ 開關終端機面板；n + t + i 都能按
      -- （不用 <C-\>：它在終端機模式跟內建跳出鍵 <C-\><C-n> 衝突。<C-_> 是後備，
      --   有些終端機把 Ctrl+/ 送成 Ctrl+_）
      --
      -- 開關的對象是「最後使用的終端機」（last_terminal），不是永遠強制跳回
      -- claude：預設是 claude，但只要透過 Ctrl+t 切換過其他終端機，
      -- last_terminal 就會變成那個，Ctrl+/ 之後開關的就是它，回到上一個
      -- 用的終端機，而不是每次都被拉回 claude。
      --
      -- 單一終端機面板原則：底部只該同時顯示一個終端機（跟 Ctrl+t 清單面板的
      -- 切換 action 邏輯一致）。開啟前先把其他開著的終端機關掉，避免 toggleterm
      -- 把它用分割視窗的方式擠進去，變成畫面上同時有兩個終端機。
      for _, key in ipairs({ "<C-/>", "<C-_>" }) do
        vim.keymap.set({ "n", "t", "i" }, key, function()
          close_terminal_zoom() -- 開關動作一律視為「回到正常大小」，避免縮放狀態殘留
          if last_terminal:is_open() then
            last_terminal:close()
          else
            for _, t in ipairs(require("toggleterm.terminal").get_all(true)) do
              if t.id ~= last_terminal.id and t:is_open() then
                t:close()
              end
            end
            last_terminal:open()
          end
          force_edgy_relayout()
        end, { desc = "開關終端機面板（最後使用的終端機）" })
      end
      -- Alt+Z 縮放/還原終端機面板。選 Alt 而不是 Ctrl 組合鍵是因為：
      -- Ctrl+Z 在終端機裡是內建的 job control（暫停前景程式，SIGTSTP），
      -- Ctrl+\ 會跟 nvim 終端機模式內建跳出鍵 <C-\><C-n> 衝突（Ctrl+t 的
      -- 實作本身就是靠送出這個序列，見下方），兩個都不能用。
      --
      -- 用蓋滿整個畫面的浮動視窗顯示同一個終端機 buffer（見上方
      -- close_terminal_zoom() 旁的說明：曾經試過直接關掉編輯器/側邊欄視窗，
      -- 但會被 edgy 的保護機制連終端機一起關掉、卡住恢復不了）。
      local function toggle_terminal_zoom()
        if not last_terminal:is_open() or not last_terminal.window or not vim.api.nvim_win_is_valid(last_terminal.window) then
          vim.notify("目前沒有開啟中的終端機可以縮放", vim.log.levels.WARN)
          return
        end
        if zoom_float_win and vim.api.nvim_win_is_valid(zoom_float_win) then
          close_terminal_zoom()
          if vim.api.nvim_win_is_valid(last_terminal.window) then
            vim.api.nvim_set_current_win(last_terminal.window)
          end
        else
          zoom_float_win = vim.api.nvim_open_win(last_terminal.bufnr, true, {
            relative = "editor",
            row = 0,
            col = 0,
            width = vim.o.columns,
            height = vim.o.lines - vim.o.cmdheight - 1, -- 扣掉 nvim 自己的 cmdline/statusline
            style = "minimal",
            border = "none",
            zindex = 50,
          })
        end
        vim.schedule(function()
          if vim.bo.buftype == "terminal" then
            vim.cmd("startinsert")
          end
        end)
      end
      vim.keymap.set({ "n", "t", "i" }, "<M-z>", toggle_terminal_zoom, { desc = "縮放/還原終端機面板（浮動視窗蓋滿畫面）" })
      -- Ctrl+t 開終端機清單面板（toggleterm-manager，見下方外掛）
      -- 一定要傳 {}：open() 沒帶 opts 時內部傳 nil 給 telescope previewer 會報錯
      vim.keymap.set("n", "<C-t>", function() require("toggleterm-manager").open({}) end, { desc = "終端機清單面板" })
      vim.keymap.set("t", "<C-t>", [[<C-\><C-n><cmd>lua require('toggleterm-manager').open({})<cr>]], { desc = "終端機清單面板" })
      -- 終端機內用 Ctrl+hjkl 移到對應視窗/pane（不用先手動跳出終端機模式）：
      -- 用 TmuxNavigate* 而非純 <C-w>h，這樣 nvim 視窗沒有目標時會 fallback
      -- 給 tmux pane（跟一般模式共用同一套 vim-tmux-navigator 邏輯）。
      -- 但終端機是版面最下面/最右邊，往下（j）、往右（l）常常兩邊都沒有目標，
      -- 這種「切不過去」的情況下停在原本的終端機視窗，就用 startinsert
      -- 補回終端機模式，避免使用者被留在 Normal 模式、還要手動按 i 才能繼續打字。
      local function term_navigate(direction)
        return function()
          local win_before = vim.api.nvim_get_current_win()
          vim.cmd("TmuxNavigate" .. direction)
          if vim.api.nvim_get_current_win() == win_before then
            vim.schedule(function()
              if vim.bo.buftype == "terminal" then
                vim.cmd("startinsert")
              end
            end)
          end
        end
      end
      vim.keymap.set("t", "<C-h>", term_navigate("Left"), { desc = "移到左邊視窗/pane" })
      vim.keymap.set("t", "<C-j>", term_navigate("Down"), { desc = "移到下面視窗/pane" })
      vim.keymap.set("t", "<C-k>", term_navigate("Up"), { desc = "移到上面視窗/pane" })
      vim.keymap.set("t", "<C-l>", term_navigate("Right"), { desc = "移到右邊視窗/pane" })

      -- 終端機視窗留白 statusline：不設的話 nvim 會用預設值顯示醜醜的
      -- term://~/code/dotfiles//12345:/bin/bash;#toggleterm#1 buffer 名稱。
      -- 快捷鍵提示已經搬到 tmux 狀態列（見 tmux.conf），這裡不用重複顯示。
      --
      -- 這一列沒辦法真的消失：nvim 的 laststatus 是全域設定，沒有「只關掉
      -- 這個視窗」的選項；laststatus=3（全部視窗共用一條）試過，但會把
      -- 編輯器自己的 statusline 也搬走、位置跟著變，不是要的效果，已還原。
      -- 空白只是視覺上盡量不顯眼，不是佔用空間的解法。
      vim.api.nvim_create_autocmd("TermOpen", {
        pattern = "term://*",
        callback = function()
          vim.opt_local.statusline = " "
        end,
      })

      -- 進入終端機時自動切 insert 模式：edgy 重新排版、或用 Ctrl+j 的 <cmd> 導航移進來時
      -- 可能停在 normal 模式導致打不進去。用 vim.schedule 延到視窗切換完成後再 startinsert，
      -- 否則同步呼叫會被導航流程之後的模式重置吃掉（停在 normal，需手動按 i）。
      vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter", "TermOpen" }, {
        pattern = "term://*",
        callback = function()
          vim.schedule(function()
            -- 只在焦點仍在終端機 buffer 時才 startinsert（排程期間焦點可能已移走）
            if vim.bo.buftype == "terminal" then
              vim.cmd("startinsert")
            end
          end)
        end,
      })

      -- 啟動於資料夾（ide 情境）時，自動開 claude 為預設底部終端機
      local function launched_on_dir()
        for i = 2, #vim.v.argv do
          local a = vim.v.argv[i]
          if a == "." or vim.fn.isdirectory(a) == 1 then
            return true
          end
        end
        return false
      end
      if launched_on_dir() then
        vim.schedule(function()
          -- 啟動後焦點就留在 claude（可直接開始下指令，不用先按 Ctrl+j）。
          -- 原本這裡開完 claude 會再排一個 wincmd k 想把焦點移回編輯器，
          -- 但實測從啟動後第一個可觀測的時間點起，焦點就一直在終端機上，
          -- 那行 wincmd k 從來沒有生效過（claude 的 on_open 之後還會
          -- term:send()，焦點會回到終端機）。既然實際行為一直是停在
          -- claude、使用起來也符合需求，就拿掉那行不生效的程式碼，
          -- 讓程式碼與實際行為一致。
          claude:open()
        end)
      end
    end,
  },
  {
    -- 版面管理：neo-tree 釘左邊（全高）、toggleterm 釘底部（只在編輯器下方，不佔 neo-tree）
    "folke/edgy.nvim",
    event = "VeryLazy",
    opts = {
      animate = { enabled = false },
      left = {
        { ft = "neo-tree", size = { width = 32 } },
      },
      bottom = {
        {
          ft = "toggleterm",
          size = { height = 15 },
          -- 只管非浮動的終端機（避免 edgy 誤管浮動視窗）
          filter = function(_buf, win)
            return vim.api.nvim_win_get_config(win).relative == ""
          end,
        },
      },
    },
  },
  {
    -- 模糊搜尋框架（供 toggleterm-manager 用，之後也能做檔案/全文搜尋）
    "nvim-telescope/telescope.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
    cmd = "Telescope",
    config = function()
      local t_actions = require("telescope.actions")
      require("telescope").setup({
        defaults = {
          mappings = {
            -- 跟整套 IDE 一致：Ctrl+j/k 移動選取（預設 C-k 會捲 Preview、C-j 沒綁）
            i = {
              ["<C-j>"] = t_actions.move_selection_next,
              ["<C-k>"] = t_actions.move_selection_previous,
              -- telescope 預設 insert 模式的 <esc> 只會退到 normal 模式（還在面板
              -- 裡），要再按一次 <esc>（normal 模式的預設綁定）才會真的關閉面板。
              -- 這裡讓 insert 模式按一次 <esc> 就直接關閉，不用按兩次。
              ["<esc>"] = t_actions.close,
            },
          },
        },
      })
    end,
  },
  {
    -- 終端機清單面板（Ctrl+t 開）：列出所有終端機、右側預覽，可切換/新增/改名/刪除
    "ryanmsnyder/toggleterm-manager.nvim",
    dependencies = {
      "akinsho/toggleterm.nvim",
      "nvim-telescope/telescope.nvim",
      "nvim-lua/plenary.nvim",
    },
    config = function()
      local tm_actions = require("toggleterm-manager").actions
      local t_actions = require("telescope.actions")
      local t_state = require("telescope.actions.state")

      -- VSCode 式「切換」：只顯示選中的終端機、隱藏其他已開啟的，並聚焦它。
      -- 不用內建 toggle_term：它只單獨開/關選中的一個，導致（a）已開的再按會被關掉、
      -- start_insert 反而落在編輯器上（編輯器變 insert）；（b）不會隱藏其他 → 兩個並排。
      local function switch_to_selected(prompt_bufnr)
        local selection = t_state.get_selected_entry()
        if selection == nil then
          return
        end
        close_terminal_zoom() -- 切換終端機一律視為「回到正常大小」
        local term = selection.value
        t_actions.close(prompt_bufnr)
        -- 底部單一面板：關掉其他開著的終端機，只留選中的
        for _, t in ipairs(require("toggleterm.terminal").get_all(true)) do
          if t.id ~= term.id and t:is_open() then
            t:close()
          end
        end
        if not term:is_open() then
          term:open()
        end
        term:focus()
        last_terminal = term -- 記住這個是「最後使用的終端機」，Ctrl+/ 之後開關它
        -- 聚焦終端機視窗後進 insert（延後避免被視窗切換的模式重置吃掉）
        vim.schedule(function()
          if vim.bo.buftype == "terminal" then
            vim.cmd("startinsert")
          end
        end)
        force_edgy_relayout()
      end

      -- 找出目前哪個視窗顯示著指定 buffer 並聚焦它（不存在就不做事）
      local function focus_win_with_buf(bufnr)
        for _, win in ipairs(vim.api.nvim_list_wins()) do
          if vim.api.nvim_win_get_buf(win) == bufnr then
            vim.api.nvim_set_current_win(win)
            return true
          end
        end
        return false
      end

      -- 新增終端機：toggleterm-manager 內建的 create_term 只會單純開一個新終端機，
      -- 不知道底部單一面板原則，如果原本就有終端機開著（例如 claude），新的會用
      -- 分割視窗擠進去，變成背景看到兩個終端機並排。這裡在建立完之後，比對建立
      -- 前後開著的終端機差異找出「剛建立的那一個」，關掉其他的只留它。
      --
      -- 關鍵：清理其他終端機時不能用 t:close()。toggleterm 的 Terminal:close()
      -- 內部（ui.close → close_split）關掉分割視窗後，會無條件把焦點跳去一個
      -- module 層級的「origin window」，而 create_term 自己內部的排程（把焦點
      -- 送回 telescope 面板）剛好會把這個 origin window 設成「剛建立的新終端機」
      -- 視窗——所以不管等多久才清理，關掉其他終端機都一定會把焦點劫走、跳去新
      -- 終端機，導致直接跳出 telescope 面板。改用 nvim_win_close 直接關視窗，
      -- 跳過這個會動到全域 origin window 的副作用。
      local function create_term_single_panel(prompt_bufnr, exit_on_action)
        close_terminal_zoom() -- 新增終端機一律視為「回到正常大小」
        local before = {}
        for _, t in ipairs(require("toggleterm.terminal").get_all(true)) do
          before[t.id] = true
        end
        tm_actions.create_term(prompt_bufnr, exit_on_action)
        vim.schedule(function()
          local terms = require("toggleterm.terminal").get_all(true)
          local created
          for _, t in ipairs(terms) do
            if not before[t.id] then
              created = t
            end
          end
          if created then
            for _, t in ipairs(terms) do
              if t.id ~= created.id and t:is_open() and t.window then
                pcall(vim.api.nvim_win_close, t.window, true)
              end
            end
            last_terminal = created
          end
          -- 保險：清理完之後如果 telescope 面板還開著，確定焦點還在它上面
          if vim.api.nvim_buf_is_valid(prompt_bufnr) then
            focus_win_with_buf(prompt_bufnr)
          end
          force_edgy_relayout()
        end)
      end

      require("toggleterm-manager").setup({
        mappings = {
          i = {
            ["<CR>"] = { action = switch_to_selected, exit_on_action = true },              -- 切換（隱藏其他）
            ["<C-i>"] = { action = create_term_single_panel, exit_on_action = false },       -- 新增
            ["<C-r>"] = { action = tm_actions.rename_term, exit_on_action = false },         -- 改名
            ["<C-d>"] = { action = tm_actions.delete_term, exit_on_action = false },         -- 刪除
          },
        },
        -- 把快捷鍵說明直接顯示在面板標題上
        titles = {
          prompt = "↵切換  C-i新增  C-r改名  C-d刪除  C-jk選取",
          results = "終端機清單",
          preview = "預覽",
        },
      })
    end,
  },
})

vim.opt.number = true
vim.opt.termguicolors = true
-- 永遠保留 git 標記欄，避免有/無 git 標記時行號欄寬度跳動
vim.opt.signcolumn = "yes"
-- edgy 建議：split 時保持畫面穩定
vim.opt.splitkeep = "screen"
-- Esc 按下去要延遲才生效：ttimeoutlen 沒設定時會退回用 timeoutlen（預設 1000ms）。
-- 終端機的方向鍵/功能鍵也是用 ESC 開頭的跳脫序列送過來，nvim 收到單一 ESC 時
-- 要等一小段時間確認後面是否還有更多 byte 才能判斷是不是完整的按鍵，這段等待
-- 預設用 timeoutlen 那麼久，感覺起來就像 Esc 按了要等一下才生效。調小
-- ttimeoutlen 讓這個判斷更快，同時保留 timeoutlen 給像 <leader>xx 這種
-- 多鍵組合鍵的等待時間。
vim.opt.ttimeoutlen = 10

-- 取得 gitgraph 圖上游標所在的 commit（用 gitgraph 的公開 API）
local function gg_commit_under_cursor()
  local ok_draw, draw = pcall(require, "gitgraph.draw")
  local ok_utils, utils = pcall(require, "gitgraph.utils")
  if not (ok_draw and ok_utils) or not draw.graph then
    return nil
  end
  local row = vim.api.nvim_win_get_cursor(0)[1]
  return utils.get_commit_from_row(draw.graph, row)
end

-- checkout 後刷新 gitgraph 圖與 gitsigns 的 git 狀態
local function gg_refresh()
  pcall(gg_sync_preview_refs)
  pcall(function()
    require("gitgraph").draw({}, { revision_range = GG_REVISION_RANGE, max_count = 5000 })
  end)
  pcall(gg_style_preview_nodes)
  pcall(function()
    require("gitsigns").refresh()
  end)
end

-- checkout 游標所在的 commit（detached HEAD，先確認）
local function gg_checkout_commit()
  local c = gg_commit_under_cursor()
  if not c then
    vim.notify("找不到游標所在的 commit", vim.log.levels.WARN)
    return
  end
  if vim.fn.confirm("checkout commit " .. c.hash .. "？（會進入 detached HEAD）", "&Yes\n&No", 2) ~= 1 then
    return
  end
  local out = vim.fn.system({ "git", "checkout", c.hash })
  if vim.v.shell_error ~= 0 then
    vim.notify("checkout 失敗：\n" .. out, vim.log.levels.ERROR)
    return
  end
  vim.notify("已 checkout " .. c.hash .. "（detached HEAD）")
  gg_refresh()
end

-- checkout 游標所在 commit 的分支（多個時用選單）
local function gg_checkout_branch()
  local c = gg_commit_under_cursor()
  if not c then
    vim.notify("找不到游標所在的 commit", vim.log.levels.WARN)
    return
  end
  local branches, seen = {}, {}
  for _, b in ipairs(c.branch_names or {}) do
    local name = b:match("->%s*(.+)$") or b
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    if name ~= "" and name ~= "HEAD" and not name:match("^tag:") and not seen[name] then
      seen[name] = true
      branches[#branches + 1] = name
    end
  end
  if #branches == 0 then
    vim.notify("這個 commit 上沒有分支可 checkout", vim.log.levels.WARN)
    return
  end
  local function do_checkout(name)
    local out = vim.fn.system({ "git", "checkout", name })
    if vim.v.shell_error ~= 0 then
      vim.notify("checkout 失敗：\n" .. out, vim.log.levels.ERROR)
      return
    end
    vim.notify("已 checkout 分支 " .. name)
    gg_refresh()
  end
  if #branches == 1 then
    do_checkout(branches[1])
  else
    vim.ui.select(branches, { prompt = "選擇要 checkout 的分支：" }, function(choice)
      if choice then
        do_checkout(choice)
      end
    end)
  end
end

-- 顯示游標所在 commit 的完整 message（浮動視窗）
local function gg_show_message()
  local c = gg_commit_under_cursor()
  if not c then
    vim.notify("找不到游標所在的 commit", vim.log.levels.WARN)
    return
  end
  local msg = vim.fn.systemlist({ "git", "show", "-s", "--format=%B", c.hash })
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, msg)
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = "wipe"
  local width = math.min(80, vim.o.columns - 4)
  local height = math.max(3, math.min(#msg + 1, vim.o.lines - 4))
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = "minimal",
    border = "rounded",
    title = " commit " .. c.hash .. " ",
    title_pos = "center",
  })
  -- 把游標移離第一個字（gitmoji），避免 block 方塊游標蓋在 emoji 上看起來像背景框
  vim.api.nvim_win_call(win, function()
    vim.cmd("normal! $")
  end)
  vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = buf, silent = true })
  vim.keymap.set("n", "<Esc>", "<cmd>close<cr>", { buffer = buf, silent = true })
end

-- gitgraph 畫面的 buffer-local 快捷鍵（which-key 會依 desc 在此 buffer 顯示）
vim.api.nvim_create_autocmd("FileType", {
  pattern = "gitgraph",
  callback = function(ev)
    local function map(lhs, fn, desc)
      vim.keymap.set("n", lhs, fn, { buffer = ev.buf, silent = true, desc = desc })
    end
    -- q：切回原本的 buffer（不關視窗，避免觸發 close_if_last_window 使 nvim 退出）
    map("q", function()
      gg_cleanup_preview_refs() -- 離開圖之後把臨時 ref 清乾淨，避免殘留舊狀態
      local prev = vim.g.gitgraph_prev_buf
      if prev and vim.api.nvim_buf_is_valid(prev) then
        vim.cmd("buffer " .. prev)
      else
        vim.cmd("enew")
      end
    end, "返回編輯器")
    map("<leader>co", gg_checkout_commit, "checkout 此 commit")
    map("<leader>cb", gg_checkout_branch, "checkout 此分支")
    map("<leader>gm", gg_show_message, "顯示完整 commit message")
    -- which-key 群組標籤（buffer-local）
    pcall(function()
      require("which-key").add({ { "<leader>c", group = "Checkout", buffer = ev.buf } })
    end)
  end,
})

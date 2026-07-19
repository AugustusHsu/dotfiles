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
          require("gitgraph").draw({}, { all = true, max_count = 5000 })
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
          claude:open()
          -- 開完 claude 後把焦點移回編輯器（不要一啟動就卡在終端機）
          vim.schedule(function()
            vim.cmd("wincmd k")
          end)
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
  pcall(function()
    require("gitgraph").draw({}, { all = true, max_count = 5000 })
  end)
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

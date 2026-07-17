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

vim.g.mapleader = " "

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
    -- 統一 Ctrl+hjkl 導航：跨 nvim 視窗與 tmux pane（純 vimscript，相容 nvim 0.9）
    "christoomey/vim-tmux-navigator",
    lazy = false,
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
        sources = { "filesystem", "git_status", "buffers" },
        -- 側邊欄頂端的來源切換器（圖示分頁）＝ VSCode activity bar 的角色
        source_selector = {
          winbar = true,
          content_layout = "center",
          sources = {
            { source = "filesystem", display_name = "󰙅 Files" },
            { source = "git_status", display_name = "󰊢 Git" },
            { source = "buffers", display_name = "󰈔 Buffers" },
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
      vim.keymap.set("n", "<leader>3", "<cmd>Neotree buffers<cr>", { desc = "側邊欄：Buffers", silent = true })
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
      -- 群組標籤：讓 <leader>g 開頭的一批顯示成「Git」
      wk.add({
        { "<leader>g", group = "Git" },
        { "<leader>1", desc = "側邊欄：Files" },
        { "<leader>2", desc = "側邊欄：Git" },
        { "<leader>3", desc = "側邊欄：Buffers" },
        { "<leader>e", desc = "側邊欄開關" },
      })
    end,
  },
})

vim.opt.number = true
vim.opt.termguicolors = true
-- 永遠保留 git 標記欄，避免有/無 git 標記時行號欄寬度跳動
vim.opt.signcolumn = "yes"

-- gitgraph 畫面按 q：切回原本的 buffer（編輯器），不關視窗——
-- 直接關視窗會讓 neo-tree 變成最後一個視窗、觸發 close_if_last_window 使 nvim 退出
vim.api.nvim_create_autocmd("FileType", {
  pattern = "gitgraph",
  callback = function(ev)
    vim.keymap.set("n", "q", function()
      local prev = vim.g.gitgraph_prev_buf
      if prev and vim.api.nvim_buf_is_valid(prev) then
        vim.cmd("buffer " .. prev)
      else
        vim.cmd("enew") -- 沒有記錄到就開一個空的，避免關視窗
      end
    end, { buffer = ev.buf, silent = true, desc = "返回編輯器" })
  end,
})

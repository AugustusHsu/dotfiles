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
          -- 用 `nvim .` 開資料夾時直接接管成 neo-tree
          hijack_netrw_behavior = "open_current",
        },
        window = {
          width = 32,
        },
      })

      -- 切換器快捷鍵（直接跳到某來源，像 VSCode Ctrl+Shift+E / G）
      vim.keymap.set("n", "<leader>e", "<cmd>Neotree toggle<cr>", { desc = "側邊欄開關", silent = true })
      vim.keymap.set("n", "<leader>1", "<cmd>Neotree filesystem<cr>", { desc = "側邊欄：Files", silent = true })
      vim.keymap.set("n", "<leader>2", "<cmd>Neotree git_status<cr>", { desc = "側邊欄：Git", silent = true })
      vim.keymap.set("n", "<leader>3", "<cmd>Neotree buffers<cr>", { desc = "側邊欄：Buffers", silent = true })

      -- 用 `nvim .` 開資料夾（或無參數）時自動開啟側邊欄
      vim.api.nvim_create_autocmd("VimEnter", {
        callback = function()
          local should = vim.fn.argc() == 0
          for i = 2, #vim.v.argv do
            local a = vim.v.argv[i]
            if a == "." or vim.fn.isdirectory(a) == 1 then
              should = true
            end
          end
          if should then
            vim.schedule(function()
              vim.cmd("Neotree show")
            end)
          end
        end,
      })
    end,
  },
})

vim.opt.number = true
vim.opt.termguicolors = true

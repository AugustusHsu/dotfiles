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
    "nvim-tree/nvim-tree.lua",
    tag = "compat-nvim-0.9",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    config = function()
      require("nvim-tree").setup({
        renderer = {
          highlight_opened_files = "name",
          highlight_modified = "name",
          indent_markers = { enable = true },
          icons = {
            show = {
              file = true,
              folder = true,
              folder_arrow = true,
              git = true,
              modified = true,
            },
          },
        },
        git = { enable = true },
        actions = {
          open_file = { quit_on_open = false },
        },
      })

      -- 用 `nvim .` 開啟資料夾時自動打開側邊欄
      vim.api.nvim_create_autocmd("VimEnter", {
        callback = function(data)
          local stat = vim.loop.fs_stat(data.file)
          if data.file == "" or (stat and stat.type == "directory") then
            require("nvim-tree.api").tree.open()
          end
        end,
      })
    end,
  },
})

vim.opt.number = true
vim.opt.termguicolors = true

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
      local function on_attach(bufnr)
        local api = require("nvim-tree.api")
        local function opts(desc)
          return { desc = "nvim-tree: " .. desc, buffer = bufnr, noremap = true, silent = true, nowait = true }
        end

        api.config.mappings.default_on_attach(bufnr)

        -- 停用改變樹狀圖根目錄的按鍵，避免不小心跳到上一層/其他資料夾把版面弄亂
        pcall(vim.keymap.del, "n", "-", { buffer = bufnr })
        pcall(vim.keymap.del, "n", "<C-]>", { buffer = bufnr })

        -- 根目錄標籤那一行（游標在第 1 行）在 nvim-tree 內部會被當成
        -- 根節點自己，按 Enter/o 開啟等同於跳到上一層；這裡包一層判斷
        -- 擋掉，同時保留標籤顯示（root_folder_label 維持預設樣式）
        local function guard_root(fn)
          return function()
            local node = api.tree.get_node_under_cursor()
            if node and not node.parent then
              return
            end
            fn()
          end
        end
        vim.keymap.set("n", "<CR>", guard_root(api.node.open.edit), opts("Open"))
        vim.keymap.set("n", "o", guard_root(api.node.open.edit), opts("Open"))
        vim.keymap.set("n", "<2-LeftMouse>", guard_root(api.node.open.edit), opts("Open"))
      end

      require("nvim-tree").setup({
        on_attach = on_attach,
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

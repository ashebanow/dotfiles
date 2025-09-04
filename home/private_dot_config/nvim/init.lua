---@diagnostic disable: undefined-global

vim.cmd([[set mouse=]])
vim.cmd([[set noswapfile]])
vim.opt.winborder = "rounded"
vim.opt.tabstop = 2
vim.opt.wrap = false
vim.opt.cursorcolumn = false
vim.opt.ignorecase = true
vim.opt.shiftwidth = 2
vim.opt.smartindent = true
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.termguicolors = true
vim.opt.undofile = true
vim.opt.signcolumn = "yes"


local map = vim.keymap.set
vim.g.mapleader = " "
map('n', '<leader>w', ':write<CR>')
-- map('n', 'mk', 'make<CR>')
-- map('n', 'co', ':cw<CR>')
map('n', '<leader>q', ':quit<CR>')
map('n', '<C-f>', ':Open .<CR>')
map('n', '<leader>v', ':e $MYVIMRC<CR>')
map('n', '<leader>z', ':e ~/.config/zsh/.zshrc<CR>')
map('n', '<leader>s', ':e #<CR>')
map('n', '<leader>S', ':bot sf #<CR>')
map({ 'n', 'v' }, '<leader>n', ':norm ')
map({ 'n', 'v' }, '<leader>y', '"+y')
map({ 'n', 'v' }, '<leader>d', '"+d')
map({ 'n', 'v' }, '<leader>c', '1z=')
map({ 'n', 'v' }, '<leader>o', ':update<CR> :source<CR>')

vim.pack.add({
    { src = "https://github.com/vague2k/vague.nvim" },
    { src = "https://github.com/stevearc/oil.nvim" },
    { src = "https://github.com/echasnovski/mini.pick" },
    { src = "https://github.com/nvim-treesitter/nvim-treesitter",             version = "main" },
    { src = "https://github.com/nvim-treesitter/nvim-treesitter-textobjects", version = "main" },
    { src = "https://github.com/chomosuke/typst-preview.nvim" },
    { src = 'https://github.com/neovim/nvim-lspconfig' },
    { src = "https://github.com/mason-org/mason.nvim" },
    { src = "https://github.com/L3MON4D3/LuaSnip" },
    { src = "https://github.com/ellisonleao/gruvbox.nvim.git",                name = "gruvbox" },
})

require "mason".setup()
require "mini.pick".setup({
    mappings = {
        choose_marked = "<C-G>"
    }
})
require "oil".setup()

map('n', '<leader>f', ":Pick files<CR>")
map('n', '<leader>h', ":Pick help<CR>")
map('n', '<leader>e', ":Oil<CR>")
map('t', '', "")
map('t', '', "")
map('n', '<leader>lf', vim.lsp.buf.format)

vim.lsp.enable(
    {
        "c",
        "clangd",
        "go",
        "javascript",
        "lua_ls",
        "markdown",
        "markdown_inline",
        "python",
        "ruby",
        "rust_analyzer",
        "svelte",
        "tinymist",
        "typescript",
        "vim",
        "vimdoc",
    }
)

-- colors
vim.cmd("colorscheme gruvbox")
-- vim.cmd(":hi statusline guibg=NONE")

-- snippets
require("luasnip").setup({ enable_autosnippets = true })
require("luasnip.loaders.from_lua").load({ paths = "~/.config/nvim/snippets/" })
local ls = require("luasnip")
map("i", "<C-e>", function() ls.expand_or_jump(1) end, { silent = true })
map({ "i", "s" }, "<C-J>", function() ls.jump(1) end, { silent = true })
map({ "i", "s" }, "<C-K>", function() ls.jump(-1) end, { silent = true })


-- treesitter

require 'nvim-treesitter.configs'.setup {
    -- A list of parser names, or "all" (the five listed parsers should always be installed)
    ensure_installed = {
        "javascript", "typescript", "python", "c", "lua",
        "vim", "vimdoc", "query", "markdown", "markdown_inline",
        "rust", "ruby", "go", "java", "cpp"
    },
    highlight = {
        enable = true,
        -- custom_captures = {
        -- 	["math"] = "math",
        -- },
        additional_vim_regex_highlighting = false,
    },
    textobjects = {
        select = {
            enable = true,
            lookahead = true,
            keymaps = {
                ["if"] = "@function.inner",
                ["af"] = "@function.outer",
                ["im"] = "@math.inner",
                ["am"] = "@math.outer",
                ["ar"] = "@return.outer",
                ["ir"] = "@return.inner",
                ["ac"] = "@class.outer",
                -- ["as"] = { query = "@local.scope", query_group = "locals", desc = "Select language scope" },
            },
        },
    },
}

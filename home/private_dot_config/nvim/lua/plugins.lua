vim.pack.add({
    { src = "https://github.com/ellisonleao/gruvbox.nvim.git",   name = "gruvbox" },
    { src = "https://github.com/rcarriga/nvim-notify" },
    { src = "https://github.com/neovim/nvim-lspconfig.git" },
    { src = "https://github.com/nvim-treesitter/nvim-treesitter" },
    { src = "https://github.com/mason-org/mason.nvim.git" },
    { src = "https://github.com/tpope/vim-sleuth" },
    { src = "https://github.com/nvim-tree/nvim-tree.lua" },
    { src = "https://github.com/nvim-lua/plenary.nvim" },
    { src = "https://github.com/nvim-telescope/telescope.nvim" },
    { src = "https://github.com/stevearc/conform.nvim" },
    { src = "https://github.com/Saghen/blink.cmp" },
    { src = "https://github.com/nvim-lualine/lualine.nvim" },
    { src = "https://github.com/echasnovski/mini.files" },
})

vim.cmd.colorscheme "gruvbox"

-- treesitter
require('nvim-treesitter.configs').setup {
    -- A list of parser names, or "all" (the five listed parsers should always be installed)
    ensure_installed = {
        "javascript", "typescript", "python", "c", "lua",
        "vim", "vimdoc", "query", "markdown", "markdown_inline",
        "rust", "ruby", "go", "java", "cpp"
    },
    sync_install = false,
    auto_install = true,
    ignore_install = {},
    highlight = {
        enable = true,
        additional_vim_regex_highlighting = false,
    },
}

-- lsp
require("mason").setup()
vim.lsp.enable({ "lua_ls", "pyright" })

vim.keymap.set("n", "<leader>lf", vim.lsp.buf.format)

-- nvim-tree

vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1
vim.opt.termguicolors = true

vim.keymap.set("n", "<C-n>", vim.cmd.NvimTreeToggle)

require("nvim-tree").setup({})

-- blink.cmp

require("blink.cmp").setup({
    {
        keymap = { preset = 'default' },
        appearance = {
            nerd_font_variant = 'mono'
        },
        completion = { documentation = { auto_show = false } },
        sources = {
            default = { 'lsp', 'path', 'snippets', 'buffer' },
        },
        fuzzy = { implementation = "prefer_rust" }
    },
    opts_extend = { "sources.default" }
})

-- telescope

local builtin = require('telescope.builtin')

function SearchClasses()
    builtin.lsp_dynamic_workspace_symbols({
        symbols = { "Class" },
        prompt_title = "Search Classes"
    })
end

function SearchFunctions()
    builtin.lsp_dynamic_workspace_symbols({
        symbols = { "Function", "Method" },
        prompt_title = "Search Functions"
    })
end

function SearchVariables()
    builtin.lsp_dynamic_workspace_symbols({
        symbols = { "Variable", "Constant" },
        prompt_title = "Search Variables"
    })
end

vim.keymap.set('n', '<C-p>', builtin.find_files, {})
vim.keymap.set('n', '<C-e>', builtin.oldfiles, {})
-- vim.keymap.set('n', '<leader>sg', builtin.git_files, {})
vim.keymap.set('n', '<leader>sf', SearchFunctions, {})
vim.keymap.set('n', '<leader>sc', SearchClasses, {})
vim.keymap.set('n', '<leader>sv', SearchVariables, {})
vim.keymap.set('n', '<leader>ss', builtin.lsp_dynamic_workspace_symbols, {})
vim.keymap.set('n', '<leader>sg', builtin.live_grep, {})
vim.keymap.set('n', '<leader>sw', builtin.grep_string, { desc = '[S]earch current [W]ord' })
vim.keymap.set('n', '<leader>sd', builtin.diagnostics, { desc = '[S]earch [D]iagnostics' })
vim.keymap.set('n', '<leader>sb', builtin.buffers, {})
vim.keymap.set('n', '<leader>sh', builtin.help_tags, {})
vim.keymap.set('n', '<leader>sq', builtin.quickfix, {})
vim.keymap.set('n', '<leader>sk', builtin.keymaps, {})

-- conform

require("conform").setup({
    format_on_save = {
        timeout_ms = 500,
        lsp_fallback = true,
    },
    formatters_by_ft = {
        lua = { "stylua" },
        json = { "jq" },
        rust = { "rustfmt" },
        python = { "black" },
        htmldjango = { "djlint" },
        html = { "djlint" },
        javascript = { "prettier" },
    },
})

-- lualine

require("lualine").setup({
})

-- mini files

require('mini.files').setup()
vim.keymap.set('n', '<M-1>', ":lua MiniFiles.open()<cr>", {})

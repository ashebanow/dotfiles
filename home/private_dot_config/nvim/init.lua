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
    { src = "https://github.com/L3MON4D3/LuaSnip" },
    { src = "https://github.com/ellisonleao/gruvbox.nvim.git",                name = "gruvbox" },
})

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

-- Language servers.
--
-- Only enable a server when its executable is actually reachable on $PATH.
-- `vim.lsp.enable()` happily registers a config for a missing binary and then
-- fails at spawn time, which litters a bare shell with errors. This way:
--
--   * plain shell        -> no servers, no noise
--   * `nix develop`/devenv shell -> whatever tools that shell provides lights up
--
-- `:LspInfo` lists what was picked up and what was skipped.
local servers = {
    "clangd",        -- C / C++
    "gopls",         -- Go
    "rust_analyzer", -- Rust
    "lua_ls",        -- Lua
    "tinymist",      -- Typst
    "pyright",       -- Python
    "ruby_lsp",      -- Ruby
    "ts_ls",         -- TypeScript / JavaScript
    "vim_ls",        -- Vimscript (vim-language-server)
    "marksman",      -- Markdown
}

local enabled, skipped = {}, {}
for _, name in ipairs(servers) do
    -- lsp/<name>.lua overrides (lua_ls, tinymist) take precedence over the
    -- bundled nvim-lspconfig defaults, matching vim.lsp.config semantics.
    local cfg = vim.lsp.config[name] or {}
    local cmd = cfg.cmd
    local exe = type(cmd) == "table" and cmd[1] or nil
    if exe and vim.fn.exepath(exe) ~= "" then
        table.insert(enabled, name)
    else
        table.insert(skipped, name)
    end
end

vim.lsp.enable(enabled)

vim.api.nvim_create_user_command("LspInfo", function()
    local active = {}
    for _, c in ipairs(vim.lsp.get_clients()) do
        active[c.name] = true
    end
    local lines = {}
    for _, name in ipairs(enabled) do
        table.insert(lines, ("  %s %s"):format(active[name] and "●" or "○", name))
    end
    for _, name in ipairs(skipped) do
        table.insert(lines, ("  · %s (not on PATH)"):format(name))
    end
    vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO, { title = "Language servers" })
end, {})

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
--
-- On the `main` branch, parsers are installed by nvim-treesitter itself and
-- highlighting is Neovim's own job (switched on per filetype). There is no
-- `nvim-treesitter.configs` module any more.
require('nvim-treesitter').setup {}

-- Async; a no-op for parsers that are already installed.
require('nvim-treesitter').install {
    "javascript", "typescript", "python", "c", "lua",
    "vim", "vimdoc", "query", "markdown", "markdown_inline",
    "rust", "ruby", "go", "java", "cpp",
}

vim.api.nvim_create_autocmd('FileType', {
    callback = function()
        -- Highlighting can fail on filetypes with no parser installed; that is
        -- expected and not worth an error message.
        pcall(vim.treesitter.start)
    end,
})

-- textobjects
require("nvim-treesitter-textobjects").setup {
    select = { lookahead = true },
}

local function select_textobject(query)
    return function()
        require("nvim-treesitter-textobjects.select").select_textobject(query, "textobjects")
    end
end

for lhs, query in pairs {
    ["if"] = "@function.inner",
    ["af"] = "@function.outer",
    ["im"] = "@math.inner",
    ["am"] = "@math.outer",
    ["ar"] = "@return.outer",
    ["ir"] = "@return.inner",
    ["ac"] = "@class.outer",
    -- ["as"] = { query = "@local.scope", query_group = "locals", desc = "Select language scope" },
} do
    map({ "x", "o" }, lhs, select_textobject(query))
end

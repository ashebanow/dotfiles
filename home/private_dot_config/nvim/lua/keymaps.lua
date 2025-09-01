function copy_visual_selection()
    local start_pos = vim.fn.getpos("'<")
    local end_pos = vim.fn.getpos("'>")
    local lines = vim.fn.getline(start_pos[2], end_pos[2])
    lines[1] = string.sub(lines[1], start_pos[3])
    lines[#lines] = string.sub(lines[#lines], 1, end_pos[3])
    local content = table.concat(lines, "\n")

    vim.fn.setreg("+", content)
    print("Copied to clipboard")
end

local function set_wrap()
    vim.opt.wrap = true
    vim.opt.linebreak = true
    vim.keymap.set('n', 'j', 'gj')
    vim.keymap.set('n', 'k', 'gk')
end

local function set_nowrap()
    vim.opt.wrap = false
    vim.opt.linebreak = false
    vim.keymap.set('n', 'j', 'j')
    vim.keymap.set('n', 'k', 'k')
end

vim.keymap.set('v', '>', '>gv', { noremap = true })
vim.keymap.set('v', '<', '<gv', { noremap = true })

vim.keymap.set('n', 'Y', 'yy')
vim.api.nvim_set_keymap("v", "<C-c>", [[:lua copy_visual_selection()<CR>]], { noremap = true, silent = true })
vim.api.nvim_set_keymap("n", "<C-c>", [[:lua vim.fn.setreg('+', vim.fn.getline('.'))<CR>]],
    { noremap = true, silent = true })

vim.keymap.set('n', '<leader>w', set_wrap)
vim.keymap.set('n', '<leader>W', set_nowrap)

vim.keymap.set("n", "<leader>ge", vim.diagnostic.goto_next)
vim.keymap.set("n", "<leader>gE", vim.diagnostic.goto_prev)

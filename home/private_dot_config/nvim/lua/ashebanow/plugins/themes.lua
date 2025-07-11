local gruvbox_material_transparent = true

return {
    -- {
    --     "f4z3r/gruvbox-material.nvim",
    --     config = function()
    --         require("gruvbox-material").setup({
    --             -- optional configuration here
    --         })
    --     end
    -- },
    -- {
    --     "kamwitsta/vinyl.nvim",
    --     config = function()
    --         require("vinyl").setup({
    --             -- optional configuration here
    --         })
    --     end
    -- },
    -- {
    --     "NLKNguyen/papercolor-theme",
    --     config = function()
    --         require("vague").setup({
    --             -- optional configuration here
    --         })
    --     end
    -- },
    {
        "vague2k/vague.nvim",
        config = function()
            -- NOTE: you do not need to call setup if you don't want to.
            require("vague").setup({
                -- optional configuration here
            })
        end
    },
}

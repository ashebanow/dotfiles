return {
    {
        "echasnovski/mini.ai",
        opts = {},
    },
    {
        "echasnovski/mini.bracketed",
        opts = {},
    },
    {
        "echasnovski/mini.surround",
        config = function()
            require("mini.surround").setup()
        end,
        opts = {},
    },
}

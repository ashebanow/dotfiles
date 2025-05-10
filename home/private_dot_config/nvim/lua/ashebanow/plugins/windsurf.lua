return {
  "Exafunction/windsurf.nvim",
  enabled = true,
  dependencies = {
    "nvim-lua/plenary.nvim",
    "hrsh7th/nvim-cmp",
  },
  config = function()
    require("codeium").setup({})
  end,
  opts = {
    -- Default configuration. See
    -- https://github.com/Exafunction/windsurf.nvim for
    -- details
  },
}

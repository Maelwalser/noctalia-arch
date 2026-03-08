return {
  "maelwalser/oil-copy.nvim",
  dependencies = { "stevearc/oil.nvim" },
  opts = {},
  config = function()
    require("oil-copy").setup()
  end,
}

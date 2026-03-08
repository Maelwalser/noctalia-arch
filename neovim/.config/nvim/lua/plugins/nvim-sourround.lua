return 
{
  'kylechui/nvim-surround',
  version = "*",
  event = "InsertEnter",   -- Load when entering insert mode
  keys = {
    { "ys", desc = "Add surrounding" },
    { "ds", desc = "Delete surrounding" },
    { "cs", desc = "Change surrounding" },
  },
  config = function()
    require("nvim-surround").setup({})
  end
}

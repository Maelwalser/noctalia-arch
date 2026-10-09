return {
  "AckslD/nvim-neoclip.lua",
  dependencies = {
    { 'kkharji/sqlite.lua',           module = 'sqlite' },
    -- neoclip needs one picker, not both. fzf-lua appears nowhere else in this
    -- config, and pulling it in here dragged it into startup for nothing.
    { 'nvim-telescope/telescope.nvim' },
  },
  config = function()
    require('neoclip').setup()
  end,
}

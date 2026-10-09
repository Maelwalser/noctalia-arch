return {
  'crnvl96/lazydocker.nvim',
  -- Reached only through <leader>ld, so declare that as the lazy trigger
  -- instead of loading the plugin on every startup.
  keys = {
    {
      '<leader>ld',
      "<Cmd>lua require('lazydocker').toggle({ engine = 'docker' })<CR>",
      mode = { 'n', 't' },
      desc = 'LazyDocker (docker)',
    },
  },
  opts = {
    window = {
      settings = {
        width = 0.618,       -- Percentage of screen width (0 to 1)
        height = 0.618,      -- Percentage of screen height (0 to 1)
        border = 'rounded',  -- See ':h nvim_open_win' border options
        relative = 'editor', -- See ':h nvim_open_win' relative options
      },
    },
  },
}

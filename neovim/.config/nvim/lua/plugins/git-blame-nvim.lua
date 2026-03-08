 return {
    'f-person/git-blame.nvim',
    event = 'VeryLazy',
    cmd = "GitBlameToggle",
    keys = {
      { "<leader>gb", "<cmd>GitBlameToggle<CR>", desc = "Toggle Git Blame" },
    },
    opts = {
      enabled = false, -- disable by default, enabled only on keymap
      date_format = '%m/%d/%y %H:%M:%S', -- more concise date format
    }
  }

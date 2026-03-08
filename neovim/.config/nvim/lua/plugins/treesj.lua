return {
  {
    "Wansmer/treesj",
    lazy = true,
    cmd = { "TSJToggle", "TSJSplit", "TSJJoin" },
    keys = {
      {        "gJ",
        "<cmd>TSJToggle<CR>",
        desc = "Toggle Split/Join",
      },
    },
    opts = {
      max_join_length = 200,
      use_default_keymaps = false
    },
  },
}

return {
  "milanglacier/minuet-ai.nvim",
  dependencies =
  { "nvim-lua/plenary.nvim" },
  opts = {
    keymaps = {
      accept_suggestion = "<S-Tab>",
      dismiss_suggestion = "<Esc>",
    },
    api_key = vim.env.GEMINI_API_KEY,
    model = "gemini-2.0-flash", -- AI model
    completion = {
      enable = true,          -- Enable completion
      frontend = "virtual_text",
    },
  },
  config = function(_, opts)
    if not opts.api_key or opts.api_key == "" then
      if vim.env.GEMINI_API_KEY and vim.env.GEMINI_API_KEY ~= "" then
        opts.api_key = vim.env.GEMINI_API_KEY
      else
        vim.notify(
          "GEMINI_API_KEY is not set for minuet-ai.nvim. It may not work correctly.",
          vim.log.levels.WARN,
          { title = "Minuet AI Plugin" }
        )
      end
    end
    require("minuet").setup(opts)
  end,
}

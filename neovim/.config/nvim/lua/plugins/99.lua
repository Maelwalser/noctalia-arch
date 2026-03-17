return {
  "ThePrimeagen/99",
  dependencies = { "nvim-telescope/telescope.nvim" },
  config = function()
    local _99 = require("99")
    
    _99.setup({
      -- Set your default starting provider (you can change this on the fly)
      -- Available options for your workflow:
      -- _99.Providers.GeminiCLIProvider
      -- _99.Providers.ClaudeCodeProvider
      provider = _99.Providers.ClaudeCodeProvider,
      
      -- Context files
      md_files = { "AGENT.md" },
    })

    -- Core 99 Keymaps (Visual mode mappings must be "v")
    vim.keymap.set("v", "<leader>9v", function() _99.visual() end, { desc = "99: AI Visual Selection" })
    vim.keymap.set("n", "<leader>9s", function() _99.search() end, { desc = "99: Search / Project Work" })
    vim.keymap.set("n", "<leader>9x", function() _99.stop_all_requests() end, { desc = "99: Stop all AI requests" })

    -- Dynamic Provider & Model Switching via Telescope
    vim.keymap.set("n", "<leader>9p", function() require("99.extensions.telescope").select_provider() end, { desc = "99: Select Provider" })
    vim.keymap.set("n", "<leader>9m", function() require("99.extensions.telescope").select_model() end, { desc = "99: Select Model" })
  end,
}

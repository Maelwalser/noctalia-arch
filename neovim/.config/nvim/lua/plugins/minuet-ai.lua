return {
  "milanglacier/minuet-ai.nvim",
  dependencies = { "nvim-lua/plenary.nvim" },
  event = "InsertEnter",
  opts = {
    provider = "openai_compatible",
    n_completions = 1,
    context_window = 8192,
    request_timeout = 8,
    throttle = 1500,
    debounce = 400,
    notify = "warn",
    provider_options = {
      openai_compatible = {
        end_point = "http://localhost:8080/v1/chat/completions",
        api_key = "TERM",
        name = "vps-ai",
        model = "default",
        optional = {
          max_tokens = 256,
          temperature = 0.2,
          top_p = 0.9,
        },
        stream = true,
      },
    },
    virtual_text = {
      auto_trigger_ft = {},
      keymap = {
        accept = "<S-Tab>",
        accept_line = "<C-l>",
        next = "<C-]>",
        prev = "<C-[>",
        dismiss = "<Esc>",
      },
    },
  },
  config = function(_, opts)
    require("minuet").setup(opts)
    vim.keymap.set("i", "<A-y>", function()
      require("minuet.virtualtext").action.next()
    end, { desc = "Minuet: trigger AI suggestion" })
    vim.keymap.set("n", "<leader>am", "<cmd>Minuet virtualtext toggle<cr>", {
      desc = "(A)i (M)inuet toggle ghost text",
    })
  end,
}

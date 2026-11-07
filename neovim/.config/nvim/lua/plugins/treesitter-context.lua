return {
  "nvim-treesitter/nvim-treesitter-context",
  event = { "BufReadPost", "BufNewFile" },
  dependencies = { "nvim-treesitter/nvim-treesitter" },
  opts = {
    -- A Claude prompt and its history are chat, not code: pinned headings
    -- would only cost rows (see lua/config/claude_prompt.lua).
    on_attach = function(buf)
      local name = vim.api.nvim_buf_get_name(buf)
      return not (name:match("/claude%-prompt%-[^/]*%.md$") or name == "claude://history")
    end,
  },
}

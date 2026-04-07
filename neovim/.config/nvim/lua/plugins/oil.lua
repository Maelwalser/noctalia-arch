return {
  'stevearc/oil.nvim',
  lazy = false,
  dependencies = { "echasnovski/mini.icons" },
  config = function()
    local ns = vim.api.nvim_create_namespace("oil_linecount")

    local function update_linecounts(bufnr)
      local oil = require("oil")
      local dir = oil.get_current_dir(bufnr)
      if not dir then
        return
      end

      vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)

      local line_count = vim.api.nvim_buf_line_count(bufnr)
      local entries = {}
      local max_width = 0

      for i = 0, line_count - 1 do
        local entry = oil.get_entry_on_line(bufnr, i + 1)
        local line_width = vim.fn.strdisplaywidth(vim.api.nvim_buf_get_lines(bufnr, i, i + 1, false)[1] or "")
        if line_width > max_width then
          max_width = line_width
        end
        if entry and entry.type == "file" then
          local path = dir .. entry.name
          local result = vim.fn.system({ "wc", "-l", path })
          local count = result:match("^%s*(%d+)")
          if count then
            table.insert(entries, { row = i, count = count })
          end
        end
      end

      local col = max_width + 2
      for _, e in ipairs(entries) do
        vim.api.nvim_buf_set_extmark(bufnr, ns, e.row, 0, {
          virt_text = { { e.count .. " lines", "Comment" } },
          virt_text_win_col = col,
        })
      end
    end

    require("oil").setup({
      keymaps = {

        -- Your other keymaps
        ["<C-s>"] = "actions.select_vsplit",
        ["<C-v>"] = "actions.select_split",
        ["<C-t>"] = "actions.select_tab",
        ["<C-p>"] = "actions.preview",
        ["<C-h>"] = false,
        ["<C-j>"] = false,
        ["<C-k>"] = false,
        ["<C-l>"] = false,
        ["q"] = "actions.close",
      },
      default_file_explorer = true,
      columns = {
        "icon",
      },
      win_options = {
        wrap = false,
        signcolumn = "no",
        cursorcolumn = false,
        foldcolumn = "0",
        spell = false,
        list = false,
        winbar = "%=%{v:lua.require('oil').get_current_dir()}%=",
        conceallevel = 3,
        concealcursor = "nvic",
      },
      view_options = {
        show_hidden = true,
      },
    })

    vim.api.nvim_create_autocmd("User", {
      pattern = "OilEnter",
      callback = function(args)
        vim.defer_fn(function()
          local bufnr = args.buf
          if vim.api.nvim_buf_is_valid(bufnr) then
            update_linecounts(bufnr)
          end
        end, 50)
      end,
    })
  end,
}

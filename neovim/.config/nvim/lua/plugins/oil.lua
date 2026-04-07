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

      for i = 0, line_count - 1 do
        local entry = oil.get_entry_on_line(bufnr, i + 1)
        if entry and entry.type == "file" then
          local path = dir .. entry.name
          local result = vim.fn.system({ "wc", "-l", path })
          local count = result:match("^%s*(%d+)")
          if count then
            table.insert(entries, { row = i, count = count, label = " lines" })
          end
        elseif entry and entry.type == "directory" and entry.name ~= ".." then
          local path = dir .. entry.name
          local result = vim.fn.system({ "find", path, "-maxdepth", "1", "-mindepth", "1", "-type", "f" })
          local file_count = 0
          if vim.v.shell_error == 0 and result ~= "" then
            for _ in result:gmatch("[^\n]+") do
              file_count = file_count + 1
            end
          end
          local result_d = vim.fn.system({ "find", path, "-maxdepth", "1", "-mindepth", "1", "-type", "d" })
          local dir_count = 0
          if vim.v.shell_error == 0 and result_d ~= "" then
            for _ in result_d:gmatch("[^\n]+") do
              dir_count = dir_count + 1
            end
          end
          local parts = {}
          if file_count > 0 then
            table.insert(parts, file_count .. (file_count == 1 and " file" or " files"))
          end
          if dir_count > 0 then
            table.insert(parts, dir_count .. (dir_count == 1 and " dir" or " dirs"))
          end
          local label = #parts > 0 and table.concat(parts, ", ") or "empty"
          table.insert(entries, { row = i, count = "", label = label })
        end
      end

      local win = vim.fn.bufwinid(bufnr)
      if win == -1 then return end
      local win_width = vim.api.nvim_win_get_width(win)
      local textoff = vim.fn.getwininfo(win)[1].textoff
      local usable = win_width - textoff
      for _, e in ipairs(entries) do
        local text = e.count .. e.label
        local text_width = vim.fn.strdisplaywidth(text)
        local col = usable - text_width - 1
        if col < 0 then col = 0 end
        vim.api.nvim_buf_set_extmark(bufnr, ns, e.row, 0, {
          virt_text = { { text, "Comment" } },
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

    vim.api.nvim_create_autocmd("WinResized", {
      callback = function()
        for _, win in ipairs(vim.v.event.windows) do
          local bufnr = vim.api.nvim_win_get_buf(win)
          if vim.bo[bufnr].filetype == "oil" then
            update_linecounts(bufnr)
          end
        end
      end,
    })
  end,
}

local ls = require("luasnip")
local s = ls.snippet
local t = ls.text_node
local f = ls.function_node
local i = ls.insert_node

-- Extract current filename
local function get_filename()
  return vim.fn.expand("%:t:r")
end

-- Create the DTO snippet
ls.add_snippets("java", {
  s("dto", {
    t({
      "import lombok.Getter;",
      "import lombok.Setter;",
      "",
      "@Getter",
      "@Setter",
      "public class "
    }),
    f(get_filename),
    t("{"),
    t({ "", "}" }),
  }),
})

-- Autocommand for new DTO files (optional - uncomment to use)
-- vim.api.nvim_create_autocmd("BufNewFile", {
--   pattern = "*DTO.java",
--   callback = function()
--     local filename = vim.fn.expand("%:t:r")
--
--     -- Insert the DTO template
--     vim.api.nvim_buf_set_lines(0, 0, 0, false, {
--       "import lombok.Getter;",
--       "import lombok.Setter;",
--       "",
--       "@Getter",
--       "@Setter",
--       "public class " .. filename .. " extends AbstractDto {",
--       "}"
--     })
--
--     -- Position cursor inside the class body
--     vim.api.nvim_win_set_cursor(0, {6, 0})  -- Updated line number to account for imports
--   end
-- })

local ls = require("luasnip")
local s = ls.snippet
local t = ls.text_node
local f = ls.function_node
local i = ls.insert_node

-- Extract entity name (filename without "Service")
local function get_entity_name()
  -- Get current filename without extension
  local filename = vim.fn.expand("%:t:r")
  
  -- Check if filename ends with "Service"
  if string.match(filename, "Service$") then
    -- Remove "Service" suffix
    return string.gsub(filename, "Service$", "")
  else
    -- Return original filename as fallback
    return filename
  end
end

-- Extract current filename
local function get_filename()
  return vim.fn.expand("%:t:r")
end

-- Create the service snippet
ls.add_snippets("java", {
  s("serv", {
    t({
      "public interface "
    }),
    f(get_filename),
    t({" {", "}"}),
  }),
})

-- Autocommand for new service files (optional - uncomment to use)
-- vim.api.nvim_create_autocmd("BufNewFile", {
--   pattern = "*Service.java",
--   callback = function()
--     local filename = vim.fn.expand("%:t:r")
--     local entity_name = string.gsub(filename, "Service$", "")
--     
--     -- Insert the service template
--     vim.api.nvim_buf_set_lines(0, 0, 0, false, {
--       "public interface " .. filename .. " extends AbstractService<" .. entity_name .. "> {",
--       "}"
--     })
--     
--     -- Position cursor inside the interface body
--     vim.api.nvim_win_set_cursor(0, {1, 0})
--   end
-- })

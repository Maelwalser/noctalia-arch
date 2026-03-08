local ls = require("luasnip")
local s = ls.snippet
local t = ls.text_node
local f = ls.function_node
local i = ls.insert_node

-- Extract entity name (filename without "Repository")
local function get_entity_name()
  -- Get current filename without extension
  local filename = vim.fn.expand("%:t:r")
  
  -- Check if filename ends with "Repository"
  if string.match(filename, "Repository$") then
    -- Remove "Repository" suffix
    return string.gsub(filename, "Repository$", "")
  else
    -- Return original filename as fallback
    return filename
  end
end

-- Extract current filename
local function get_filename()
  return vim.fn.expand("%:t:r")
end

-- Create the repository snippet
ls.add_snippets("java", {
  s("repo", {
    t({
      "import org.springframework.stereotype.Repository;",
      "",
      "@Repository",
      "public interface "
    }),
    f(get_filename),
    t({" {", "}"}),
  }),
})

-- Autocommand for new repository files (optional - uncomment to use)
-- vim.api.nvim_create_autocmd("BufNewFile", {
--   pattern = "*Repository.java",
--   callback = function()
--     local filename = vim.fn.expand("%:t:r")
--     local entity_name = string.gsub(filename, "Repository$", "")
--     
--     -- Insert the repository template
--     vim.api.nvim_buf_set_lines(0, 0, 0, false, {
--       "import org.springframework.stereotype.Repository;",
--       "",
--       "@Repository",
--       "public interface " .. filename .. " extends AbstractRepository<" .. entity_name .. "> {",
--       "}"
--     })
--     
--     -- Position cursor inside the interface body
--     vim.api.nvim_win_set_cursor(0, {2, 0})
--   end
-- })

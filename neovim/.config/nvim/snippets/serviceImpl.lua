local ls = require("luasnip")
local s = ls.snippet
local t = ls.text_node
local f = ls.function_node
local i = ls.insert_node

-- Extract entity name (filename without "ServiceImpl")
local function get_entity_name()
  -- Get current filename without extension
  local filename = vim.fn.expand("%:t:r")
  
  -- Check if filename ends with "ServiceImpl"
  if string.match(filename, "ServiceImpl$") then
    -- Remove "ServiceImpl" suffix
    return string.gsub(filename, "ServiceImpl$", "")
  else
    -- Return original filename as fallback
    return filename
  end
end

-- Extract service interface name (filename without "Impl")
local function get_service_interface_name()
  -- Get current filename without extension
  local filename = vim.fn.expand("%:t:r")
  
  -- Check if filename ends with "Impl"
  if string.match(filename, "Impl$") then
    -- Remove "Impl" suffix
    return string.gsub(filename, "Impl$", "")
  else
    -- Return original filename + "Service" as fallback
    return filename .. "Service"
  end
end

-- Extract current filename
local function get_filename()
  return vim.fn.expand("%:t:r")
end

-- Create the service implementation snippet
ls.add_snippets("java", {
  s("servimpl", {
    t({
      "import org.springframework.stereotype.Service;",
      "",
      "@Service",
      "public class "
    }),
    f(get_filename),
    t(" implements "),
    f(get_service_interface_name),
    t({" {", "    public "}),
    f(get_filename),
    t("("),
    t(") {"),
    t({"", "", "    }", "}"}),
  }),
})

-- Autocommand for new service implementation files (optional - uncomment to use)
-- vim.api.nvim_create_autocmd("BufNewFile", {
--   pattern = "*ServiceImpl.java",
--   callback = function()
--     local filename = vim.fn.expand("%:t:r")
--     local entity_name = string.gsub(filename, "ServiceImpl$", "")
--     local service_interface = string.gsub(filename, "Impl$", "")
--     
--     -- Insert the service implementation template
--     vim.api.nvim_buf_set_lines(0, 0, 0, false, {
--       "import org.springframework.stereotype.Service;",
--       "",
--       "@Service",
--       "public class " .. filename .. " extends AbstractServiceImpl<" .. entity_name .. "> implements " .. service_interface .. " {",
--       "    public " .. filename .. "(AbstractRepository<" .. entity_name .. "> repository) {",
--       "        super(repository);",
--       "    }",
--       "}"
--     })
--     
--     -- Position cursor inside the class body before the constructor
--     vim.api.nvim_win_set_cursor(0, {4, 0})  -- Updated line number to account for import
--   end
-- })

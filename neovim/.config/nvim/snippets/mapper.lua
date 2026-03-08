local ls = require("luasnip")
local s = ls.snippet
local t = ls.text_node
local f = ls.function_node
local i = ls.insert_node

-- Extract entity name (filename without "Mapper")
local function get_entity_name()
  -- Get current filename without extension
  local filename = vim.fn.expand("%:t:r")
  
  -- Check if filename ends with "Mapper"
  if string.match(filename, "Mapper$") then
    -- Remove "Mapper" suffix
    return string.gsub(filename, "Mapper$", "")
  else
    -- Return original filename as fallback
    return filename
  end
end

-- Extract DTO class name
local function get_dto_class_name()
  return get_entity_name() .. "Dto"
end

-- Extract current filename
local function get_filename()
  return vim.fn.expand("%:t:r")
end

-- Create the mapper snippet
ls.add_snippets("java", {
  s("mapper", {
    t({
      "import org.mapstruct.Mapper;",
      "import org.mapstruct.ReportingPolicy;",
      "",
      "@Mapper(componentModel = \"spring\", unmappedTargetPolicy = ReportingPolicy.IGNORE)",
      "public interface "
    }),
    f(get_filename),
    t(" extends AbstractMapper<"),
    f(get_entity_name),
    t(", "),
    f(get_dto_class_name),
    t({"> {", "}"}),
  }),
})

-- Autocommand for new mapper files (optional - uncomment to use)
-- vim.api.nvim_create_autocmd("BufNewFile", {
--   pattern = "*Mapper.java",
--   callback = function()
--     local filename = vim.fn.expand("%:t:r")
--     local entity_name = string.gsub(filename, "Mapper$", "")
--     local dto_name = entity_name .. "Dto"
--     
--     -- Insert the mapper template
--     vim.api.nvim_buf_set_lines(0, 0, 0, false, {
--       "import org.mapstruct.Mapper;",
--       "import org.mapstruct.ReportingPolicy;",
--       "",
--       "@Mapper(componentModel = \"spring\", unmappedTargetPolicy = ReportingPolicy.IGNORE)",
--       "public interface " .. filename .. " extends AbstractMapper<" .. entity_name .. ", " .. dto_name .. "> {",
--       "}"
--     })
--     
--     -- Position cursor inside the interface body
--     vim.api.nvim_win_set_cursor(0, {5, 0})  -- Updated line number to account for imports
--   end
-- })

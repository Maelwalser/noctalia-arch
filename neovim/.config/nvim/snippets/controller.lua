local ls = require("luasnip")
local s = ls.snippet
local t = ls.text_node
local f = ls.function_node
local i = ls.insert_node

local function get_entity_name()
  local filename = vim.fn.expand("%:t:r")
  if string.match(filename, "Controller$") then
    return string.gsub(filename, "Controller$", "")
  else
    return filename
  end
end

local function get_entity_name_lowercase()
  local entity = get_entity_name()
  return string.lower(string.sub(entity, 1, 1)) .. string.sub(entity, 2)
end

local function get_service_class_name()
  return get_entity_name() .. "Service"
end

local function get_service_variable_name()
  return get_entity_name_lowercase() .. "Service"
end

-- Extract current filename
local function get_filename()
  return vim.fn.expand("%:t:r")
end

-- Create the controller snippet
ls.add_snippets("java", {
  s("contr", {
    t({
      "import org.springframework.web.bind.annotation.RequestMapping;",
      "import org.springframework.web.bind.annotation.RestController;",
      "",
      "@RestController",
      "@RequestMapping(\"/{"
    }),
    f(get_entity_name_lowercase),
    t("}\")"),
    t({
      "",
      "public class "
    }),
    f(get_filename),
    t(" {"),
    t({
      "",
      "    private final "
    }),
    f(get_service_class_name),
    t(" "),
    f(get_service_variable_name),
    t(";"),
    t({
      "",
      "    public "
    }),
    f(get_filename),
    t("("),
    f(get_service_class_name),
    t(" "),
    f(get_service_variable_name),
    t(") {"),
    t({
      "",
      "        this."
    }),
    f(get_service_variable_name),
    t(" = "),
    f(get_service_variable_name),
    t(";"),
    t({
      "",
      "    }",
      "}"
    }),
  }),
})

-- Autocommand for new controller files (optional - uncomment to use)
-- vim.api.nvim_create_autocmd("BufNewFile", {
--   pattern = "*Controller.java",
--   callback = function()
--     local filename = vim.fn.expand("%:t:r")
--     local entity_name = string.gsub(filename, "Controller$", "")
--     local entity_lowercase = string.lower(string.sub(entity_name, 1, 1)) .. string.sub(entity_name, 2)
--     local service_class = entity_name .. "Service"
--     local service_var = entity_lowercase .. "Service"
--     
--     -- Insert the controller template
--     vim.api.nvim_buf_set_lines(0, 0, 0, false, {
--       "import org.springframework.web.bind.annotation.RequestMapping;",
--       "import org.springframework.web.bind.annotation.RestController;",
--       "",
--       "@RestController",
--       "@RequestMapping(\"/" .. entity_lowercase .. "\")",
--       "public class " .. filename .. " {",
--       "    private final " .. service_class .. " " .. service_var .. ";",
--       "",
--       "    public " .. filename .. "(" .. service_class .. " " .. service_var .. ") {",
--       "        this." .. service_var .. " = " .. service_var .. ";",
--       "    }",
--       "}"
--     })
--     
--     -- Position cursor at a good spot to start adding methods
--     vim.api.nvim_win_set_cursor(0, {10, 0})  -- Updated line number to account for imports
--   end
-- })

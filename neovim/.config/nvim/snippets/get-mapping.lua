local ls = require("luasnip")
local s = ls.snippet
local t = ls.text_node
local f = ls.function_node
local i = ls.insert_node

-- Extract base name (filename without "Controller")
local function get_base_name()
  -- Get current filename without extension
  local filename = vim.fn.expand("%:t:r")

  -- Check if filename ends with "Controller"
  if string.match(filename, "Controller$") then
    -- Remove "Controller" suffix
    return string.gsub(filename, "Controller$", "")
  else
    -- Return original filename as fallback
    return filename
  end
end

-- Get base name in lowercase
local function get_base_name_lower()
  return string.lower(get_base_name())
end

-- Get DTO type name (BaseName + "Dto")
local function get_dto_type()
  return get_base_name() .. "Dto"
end

-- Get resource ID variable name (lowercaseBaseName + "Id")
local function get_id_var()
  return string.lower(get_base_name()) .. "Id"
end

-- Create the GetMapping snippet
ls.add_snippets("java", {
  s("Get", {
    t("@GetMapping(\"/{"),
    f(get_id_var),
    t("}\")"),
    t({ "", "public ResponseEntity<" }),
    f(get_dto_type),
    t("> get"),
    f(get_base_name),
    t("(@PathVariable UUID "),
    f(get_id_var),
    t(") {"),
    t({ "", "    return ResponseEntity.status(HttpStatus.OK).body(" }),
    i(1, ""),
    t({ ");", "}" }),
  }),
})

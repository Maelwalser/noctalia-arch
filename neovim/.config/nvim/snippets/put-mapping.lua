local ls = require("luasnip")
local s = ls.snippet
local t = ls.text_node
local f = ls.function_node
local i = ls.insert_node

-- Create helper functions for name extraction
local function get_base_name()
  local filename = vim.fn.expand("%:t:r")
  if string.match(filename, "Controller$") then
    return string.gsub(filename, "Controller$", "")
  else
    return filename
  end
end

-- Create the PutMapping snippet
ls.add_snippets("java", {
  s("Put", {
    t("@PutMapping(\"/"),
    f(function() 
      return string.lower(get_base_name()) .. "Id"
    end),
    t("\")"),
    t({"", "public ResponseEntity<"}),
    f(function()
      return get_base_name() .. "Dto"
    end),
    t("> put"),
    f(function()
      return get_base_name()
    end),
    t("(@PathVariable UUID "),
    f(function()
      return string.lower(get_base_name()) .. "Id"
    end),
    t(", @RequestBody "),
    f(function()
      return get_base_name() .. "Dto"
    end),
    t(" "),
    f(function()
      local baseName = get_base_name()
      local firstChar = string.sub(baseName, 1, 1):lower()
      local rest = string.sub(baseName, 2)
      return firstChar .. rest .. "Dto"
    end),
    t(") {"),
    t({"", "    return ResponseEntity.status(HttpStatus.OK).body("}),
    i(1, ""),
    t({");", "}"}),
  }),
})

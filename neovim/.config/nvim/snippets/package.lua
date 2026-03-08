local ls = require("luasnip")
local s = ls.snippet
local t = ls.text_node
local f = ls.function_node
local i = ls.insert_node

-- This function extracts the package name from the file path
local function extract_package_name()
  -- Get the full path of the current file
  local file_path = vim.fn.expand("%:p")
  
  -- Print the file path for debugging
  
  -- Normalize path separators (convert Windows backslashes to forward slashes)
  local normalized_path = string.gsub(file_path, "\\", "/")
  
  -- Look for src/main/java or src/test/java patterns
  local src_pattern = "/src/main/java/"
  local src_test_pattern = "/src/test/java/"
  
  -- Choose which pattern to use
  local pattern_start = string.find(normalized_path, src_pattern) or string.find(normalized_path, src_test_pattern)
  local pattern = string.find(normalized_path, src_pattern) and src_pattern or 
                 (string.find(normalized_path, src_test_pattern) and src_test_pattern or nil)
  
  if pattern and pattern_start then
    
    -- Extract everything after the pattern
    local package_part = string.sub(normalized_path, pattern_start + string.len(pattern))
    
    -- Remove the Java filename at the end
    local package_path = string.gsub(package_part, "/[^/]+%.java$", "")
    
    -- Replace slashes with dots
    local package_name = string.gsub(package_path, "/", ".")
    
    if package_name and package_name ~= "" then
      return package_name
    end
  else
    
    -- Fallback approach: look for java directory and extract org/comparink portion
    local java_index = string.find(normalized_path, "/java/")
    if java_index then
      local after_java = string.sub(normalized_path, java_index + 6)  -- 6 is length of "/java/"
      local package_path = string.gsub(after_java, "/[^/]+%.java$", "")
      local package_name = string.gsub(package_path, "/", ".")
      return package_name
    end
  end
  
  -- Nothing worked
  return nil
end

-- Create the snippet
ls.add_snippets("java", {
  s("pkg", {
    f(function()
     local package_name = extract_package_name()
      
      -- Ensure we display the package clause correctly
      if package_name then
        return "package " .. package_name .. ";"
      else
        return "package "
      end
    end),
    i(1, ""),
    f(function(args, snip)
      local package_name = extract_package_name()
      return package_name and "" or ";"
    end),
  }),
})


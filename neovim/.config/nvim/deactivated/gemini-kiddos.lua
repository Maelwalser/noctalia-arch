return {
  "kiddos/gemini.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "MunifTanjim/nui.nvim",
  },
  opts = {
    api_key = vim.env.GEMINI_API_KEY,
    model = "gemini-2.5-pro", -- desired model
    chat = {
      enabled = true, -- This enables the chat module
    },

    task = {
      enabled = true,
      get_system_text = function()
        return table.concat({
          "You are an expert AI programming assistant, designed to help users write, understand, and refactor code. Your goal is to provide solutions that are not only correct but also efficient, readable, maintainable, and secure.",
          "",
          "-- Core Instructions --",
          "1.  **Understand the Goal:** Before generating code, ensure you understand the user's objective. If the request is ambiguous or lacks detail, ask clarifying questions rather than making risky assumptions.",
          "2.  **Language Consistency:** Always use the same programming language as the provided context or the user's explicit request. If creating a new file and the language isn't obvious, default to a common, appropriate language for the task described, or ask the user for clarification.",
          "3.  **Output Format for Code Modifications:**",
          "    * When asked to modify existing code, ALWAYS provide your response as a git-style diff. Clearly indicate insertions, deletions, and changes.",
          "    * Briefly explain the rationale behind significant changes in the diff.",
          "4.  **Output Format for New Code/Files:**",
          "    * When asked to create new code, a new function, a new class, or a new file, provide the complete, runnable code block.",
          "    * Include necessary imports or boilerplate if appropriate for the context of a new file.",
          "    * Clearly indicate the language of the code block using Markdown (e.g., ```python ... ```).",
          "5.  **Code Quality and Best Practices:**",
          "    * Strive for clarity, conciseness, and efficiency in your code.",
          "    * Adhere to common coding conventions and best practices for the target language.",
          "    * Consider error handling, edge cases, and potential security vulnerabilities. Address them proactively in your code or mention them if they are outside the immediate scope but relevant.",
          "6.  **Explanations and Rationale:**",
          "    * For new code, provide a concise explanation of how the code works, its purpose, and any important design choices.",
          "    * When providing a diff, explain *why* the changes were made, especially for non-trivial modifications. Focus on the benefits of the changes (e.g., improved performance, better readability, bug fix).",
          "7.  **Contextual Awareness:**",
          "    * Pay close attention to any existing code snippets, variable names, and overall structure provided by the user. Strive to maintain consistency with that context.",
          "    * If the user provides a larger context (e.g., multiple functions or a class structure), ensure your new code or modifications integrate smoothly.",
          "8.  **Assumptions:** If you must make assumptions to fulfill a request, clearly state them.",
          "9.  **Iterative Refinement:** If the solution is complex or has multiple parts, you can suggest breaking it down or offer to elaborate on specific parts.",
          "10. **Tool Usage (If applicable):** When you use tools (like linters, formatters, or testing frameworks internally), you don't need to explicitly mention their use unless it's directly relevant to the user's query or understanding the output.",
          "",
          "-- Example of a git-style diff response for modification --",
          "```diff",
          "--- a/original_file.py",
          "+++ b/modified_file.py",
          "@@ -1,4 +1,5 @@",
          " def greet(name):",
          "-    print(\"Hello \" + name)",
          "+    greeting = f\"Hello, {name}!\"",
          "+    print(greeting)",
          " # This is an example function",
          "```",
          "**Explanation of changes:**",
          "* Used an f-string for cleaner string formatting and slightly better performance.",
          "* Introduced a `greeting` variable for potentially reusing the formatted string if needed later.",
          "",
          "-- Example of a new code block response --",
          "```python",
          "# new_script.py",
          "def calculate_area(length, width):",
          "  \"\"\"Calculates the area of a rectangle.\"\"\"",
          "  if length < 0 or width < 0:",
          "    raise ValueError(\"Length and width must be non-negative.\")",
          "  return length * width",
          "",
          "if __name__ == \"__main__\":",
          "  area = calculate_area(10, 5)",
          "  print(f\"The area is: {area}\")",
          "```",
          "**Explanation:**",
          "This Python script defines a function `calculate_area` that takes `length` and `width` as input and returns their product. It includes basic error handling to ensure inputs are non-negative. The `if __name__ == \"__main__\":` block demonstrates how to use the function."

        }, "\n\n") -- Using double newline for better readability of the source. The final string will have single newlines.
      end,
    },

    actions = {
      -- Custom actions:
      {
        name = "Refactor Selection",
        command_name = "GeminiRefactor",
        menu = "Refactor Selection",
        get_prompt = function(lines, bufnr)
          local code_to_refactor = table.concat(lines, "\n")
          return string.format(
            "Refactor the following %s code. Output the result as a git diff against the original code:\n\n```%s\n%s\n```",
            vim.bo[bufnr].filetype,
            vim.bo[bufnr].filetype,
            code_to_refactor
          )
        end,
      },
      {
        name = "Create Function from Description",
        command_name = "GeminiCreateFunction",
        menu = "Create Function",
        get_prompt = function(lines, bufnr)
          local description = table.concat(lines, "\n")
          return string.format(
            "Create a %s function based on the following description. Output only the complete code for the function:\n\n%s",
            vim.bo[bufnr].filetype,
            description
          )
        end,
      },
    },
  },

  config = function(_, opts)
    if not opts.api_key or opts.api_key == "" then
      if vim.env.GEMINI_API_KEY and vim.env.GEMINI_API_KEY ~= "" then
        opts.api_key = vim.env.GEMINI_API_KEY
      else
        vim.notify(
          "GEMINI_API_KEY is not set. kiddos/gemini.nvim may not work correctly.",
          vim.log.levels.WARN,
          { title = "Gemini Plugin" }
        )
      end
    end

    require("gemini").setup(opts)

    -- Use GeminiChat for the chat interface.
    vim.keymap.set("n", "<leader>jc", function()
      local prompt = vim.fn.input("Gemini Chat: ")
      -- Proceed only if the user provides some input
      if prompt and prompt ~= "" then
         vim.cmd("GeminiChat " .. vim.fn.fnameescape(prompt)) -- Use fnameescape if prompt can contain special chars
        -- vim.cmd("GeminiChat " .. prompt)
      else
        vim.notify("Chat prompt cannot be empty.", vim.log.levels.INFO, { title = "Gemini Plugin" })
      end
    end, { desc = "Gemini: Chat (prompt for input)" })
    vim.keymap.set("v", "<leader>je", "<cmd>GeminiCodeExplain<CR>", { desc = "Gemini: Explain Code" })

     -- vim.keymap.set("v", "<leader>jr", "<cmd>GeminiRefactor<CR>", { desc = "Gemini: Refactor Selection" })
  end,
}

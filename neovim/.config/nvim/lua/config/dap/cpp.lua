local dap = require("dap")

-- Named "codelldb" because cmake-tools.nvim's :CMakeDebug looks the adapter up
-- by that type.
dap.adapters.codelldb = {
  type = "server",
  port = "${port}",
  executable = {
    command = vim.fn.stdpath("data") .. "/mason/bin/codelldb",
    args = { "--port", "${port}" },
  },
}

local configurations = {
  {
    type = "codelldb",
    name = "Launch executable",
    request = "launch",
    program = function()
      return vim.fn.input("Path to executable: ", vim.fn.getcwd() .. "/", "file")
    end,
    cwd = "${workspaceFolder}",
    stopOnEntry = false,
  },
  {
    type = "codelldb",
    name = "Launch executable with arguments",
    request = "launch",
    program = function()
      return vim.fn.input("Path to executable: ", vim.fn.getcwd() .. "/", "file")
    end,
    args = function()
      return vim.split(vim.fn.input("Arguments: "), " ", { trimempty = true })
    end,
    cwd = "${workspaceFolder}",
    stopOnEntry = false,
  },
  {
    type = "codelldb",
    name = "Attach to process",
    request = "attach",
    pid = require("dap.utils").pick_process,
  },
}

dap.configurations.c = configurations
dap.configurations.cpp = configurations

return dap

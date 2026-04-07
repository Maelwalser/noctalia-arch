local dap = require("dap")

dap.adapters.go = {
  type = "server",
  port = "${port}",
  executable = {
    command = vim.fn.stdpath("data") .. "/mason/bin/go-debug-adapter",
    args = { "-port", "${port}" },
  },
}

dap.configurations.go = {
  {
    type = "go",
    name = "Debug file",
    request = "launch",
    program = "${file}",
  },
  {
    type = "go",
    name = "Debug package",
    request = "launch",
    program = "${fileDirname}",
  },
  {
    type = "go",
    name = "Debug test file",
    request = "launch",
    mode = "test",
    program = "${file}",
  },
  {
    type = "go",
    name = "Debug test package",
    request = "launch",
    mode = "test",
    program = "${fileDirname}",
  },
  {
    type = "go",
    name = "Attach to process",
    request = "attach",
    mode = "local",
    processId = require("dap.utils").pick_process,
  },
}

return dap

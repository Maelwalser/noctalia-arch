local dap = require("dap")

dap.adapters["pwa-node"] = {
  type = "server",
  host = "localhost",
  port = "${port}",
  executable = {
    command = "node",
    args = {
      vim.fn.stdpath("data") .. "/mason/packages/js-debug-adapter/js-debug/src/dapDebugServer.js",
      "${port}",
    },
  },
}

-- Shared configurations for JS/TS
local js_configs = {
  {
    type = "pwa-node",
    request = "launch",
    name = "Launch file",
    program = "${file}",
    cwd = "${workspaceFolder}",
  },
  {
    type = "pwa-node",
    request = "attach",
    name = "Attach to process",
    processId = require("dap.utils").pick_process,
    cwd = "${workspaceFolder}",
  },
  {
    type = "pwa-node",
    request = "launch",
    name = "Launch test (Jest)",
    runtimeExecutable = "node",
    runtimeArgs = { "./node_modules/jest/bin/jest.js", "--runInBand" },
    rootPath = "${workspaceFolder}",
    cwd = "${workspaceFolder}",
    console = "integratedTerminal",
    internalConsoleOptions = "neverOpen",
  },
}

dap.configurations.javascript = js_configs
dap.configurations.typescript = js_configs
dap.configurations.javascriptreact = js_configs
dap.configurations.typescriptreact = js_configs

return dap

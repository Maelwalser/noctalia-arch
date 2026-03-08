local dap = require("dap")

if not dap.adapters.python then
  dap.adapters.python = function(cb, config)
    if config.request == "attach" then
      -- For attach, we require the host and port.
      -- This is a basic example; you might want a more robust way to get this info.
      local port = tonumber(vim.fn.input("Port: ", "5678"))
      local host = vim.fn.input("Host: ", "127.0.0.1")
      cb({
        type = "server",
        port = port,
        host = host,
        options = {
          source_filetype = "python",
        },
      })
    else -- launch
      -- For launch, debugpy starts its own server.
      -- The pythonPath will be crucial here to use the correct venv.
      local venv_python = vim.fn.exepath(config.pythonPath or "python")
      if venv_python == "" then
        venv_python = "python" -- fallback to just 'python' in PATH
      end

      cb({
        type = "executable",
        command = venv_python, -- Use the python from the venv
        args = { "-m", "debugpy.adapter" },
        options = {
          source_filetype = "python",
        },
      })
    end
  end
end

dap.configurations.python = {
  {
    type = "python", -- This must match the adapter name registered in dap.adapters
    request = "launch",
    name = "Launch file",
    program = "${file}", -- Path to the program to debug
    pythonPath = function()
      -- Attempt to get python from an active virtualenv
      local venv = os.getenv("VIRTUAL_ENV")
      if venv and venv ~= "" then
        return venv .. "/bin/python" -- Adjust for Windows if necessary (\Scripts\python.exe)
      end
      -- Fallback or prompt if not in a venv or if specific selection is needed
      -- return vim.fn.input("Path to python executable: ", vim.fn.exepath("python") or "python", "file")
      return vim.fn.exepath("python") or "python" -- Basic fallback
    end,
    -- stopOnEntry = false,
    -- console = "integratedTerminal", -- "internalConsole", "integratedTerminal", "externalTerminal"
    -- justMyCode = true, -- Set to false to step into library code
    -- args = function()
    --   local input_args = vim.fn.input("Arguments: ")
    --   local result_args = {}
    --   for Darg in string.gmatch(input_args, "[^%s]+") do
    --     table.insert(result_args, Darg)
    --   end
    --   return result_args
    -- end,
  },
  -- Example: Django launch configuration
  -- {
  --   type = "python",
  --   request = "launch",
  --   name = "Launch Django",
  --   program = "${workspaceFolder}/manage.py",
  --   args = { "runserver" },
  --   django = true,
  --   justMyCode = true,
  --   pythonPath = function() ... end,
  -- },
  {
    type = "python",
    request = "attach",
    name = "Attach to process",
    processId = require("dap.utils").pick_process,
    connect = {
      port = 5678, -- Default debugpy port, ensure this matches what the process is listening on
      host = "127.0.0.1",
    },
    pathMappings = {
      {
        localPath = "${workspaceFolder}",
        remotePath = ".", -- Adjust if your remote root is different
      },
    },
  },
}

return dap

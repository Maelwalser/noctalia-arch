return {
  "folke/snacks.nvim",
  priority = 1000,
  lazy = false,
  init = function()
    vim.api.nvim_create_autocmd("User", {
      pattern = "OilActionsPost",
      callback = function(event)
        if event.data.actions.type == "move" then
          Snacks.rename.on_rename_file(event.data.actions.src_url, event.data.actions.dest_url)
        end
      end,
    })
  end,
  keys = {
    {
      "<leader>bd",
      function()
        Snacks.bufdelete()
      end,
      desc = "Buffer delete",
      mode = "n",
    },
    {
      "<leader>ba",
      function()
        Snacks.bufdelete.all()
      end,
      desc = "Buffer delete all",
      mode = "n",
    },
    {
      "<leader>bo",
      function()
        Snacks.bufdelete.other()
      end,
      desc = "Buffer delete other",
      mode = "n",
    },
    {
      "<leader>bz",
      function()
        Snacks.zen()
      end,
      desc = "Toggle Zen Mode",
      mode = "n",
    },
  },
  opts = {
    bigfile = { enabled = true },
    dashboard = {
      preset = {
        pick = function(cmd, opts)
          local cmds = {
            files = "find_files",
            live_grep = "live_grep",
            oldfiles = "oldfiles",
          }
          require("telescope.builtin")[cmds[cmd] or cmd](opts or {})
        end,
        ---@type snacks.dashboard.Item[]
        keys = {
          { icon = " ", key = "f", desc = "Find File", action = ":lua Snacks.dashboard.pick('files')" },
          { icon = " ", key = "n", desc = "New File", action = ":ene | startinsert" },
          { icon = " ", key = "t", desc = "Find Text", action = ":lua Snacks.dashboard.pick('live_grep')" },
          { icon = " ", key = "r", desc = "Recent Files", action = ":lua Snacks.dashboard.pick('oldfiles')" },
          {
            icon = " ",
            key = "c",
            desc = "Config",
            action = ":lua Snacks.dashboard.pick('files', {cwd = vim.fn.stdpath('config')})",
          },
          { icon = " ", key = "s", desc = "Restore Session", section = "session" },
          { icon = "󰒲 ", key = "l", desc = "Lazy", action = ":Lazy", enabled = package.loaded.lazy ~= nil },
          { icon = " ", key = "q", desc = "Quit", action = ":qa" },
        },
        -- Only the classic theme shows the wordmark; see the header section below.
        header = [[
 _______  _______  _______  _                  _________ _______
(       )(  ___  )(  ____ \( \        |\     /|\__   __/(       )
| () () || (   ) || (    \/| (        | )   ( |   ) (   | () () |
| || || || (___) || (__    | |        | |   | |   | |   | || || |
| |(_)| ||  ___  ||  __)   | |        ( (   ) )   | |   | |(_)| |
| |   | || (   ) || (      | |         \ \_/ /    | |   | |   | |
| )   ( || )   ( || (____/\| (____/\    \   /  ___) (___| )   ( |
|/     \||/     \|(_______/(_______/     \_/   \_______/|/     \|
]],
      },
      sections = {
        -- ACID//HUD emblem (octant block art rendered by `hud-build`, like the
        -- Claude Code logo) instead of the wordmark. A function section is
        -- re-evaluated on resize, so the size follows the window height.
        function()
          if require("config.dotfiles_theme") ~= "acid" then
            return vim.o.columns >= 70 and { section = "header" } or nil
          end
          local name = vim.o.lines >= 44 and "nvim-header-large.txt" or "nvim-header.txt"
          local f = io.open(vim.fn.expand("~/.local/share/hud/" .. name), "r")
          if not f then
            return nil
          end
          local emblem = f:read("*a"):gsub("\n$", "")
          f:close()
          return { header = emblem, padding = 2 }
        end,
        {
          section = "keys",
          indent = 1,
          padding = 1,
        },
        { section = "recent_files", icon = " ", title = "Recent Files", indent = 3, padding = 2 },
        { section = "startup" },
      },
    },
    explorer = { enabled = false },
    indent = { enabled = true },
    input = { enabled = false },
    picker = { enabled = false },
    notifier = { enabled = false },
    quickfile = { enabled = true },
    scope = { enabled = false },
    statuscolumn = { enabled = false },
    words = { enabled = false },
    rename = { enabled = true },
    image = { enabled = false },
    zen = {
      enabled = true,
      toggles = {
        ufo = true,
        dim = true,
        git_signs = false,
        diagnostics = false,
        line_number = false,
        relative_number = false,
        signcolumn = "no",
        indent = false,
      },
    },
  },
  config = function(_, opts)
    require("snacks").setup(opts)

    local p = require("config.palette")
    local set = function(name, val)
      vim.api.nvim_set_hl(0, name, val)
    end
    if require("config.dotfiles_theme") == "acid" then
      -- p.blue is the accent slot (acid under the ACID//HUD palette).
      set("SnacksDashboardHeader", { fg = p.blue, bold = true })
      set("SnacksDashboardTitle", { fg = p.fg, bold = true })
      set("SnacksDashboardIcon", { fg = p.blue })
      set("SnacksDashboardKey", { fg = p.blue, bold = true })
    else
      set("SnacksDashboardHeader", { fg = p.purple, bold = true })
      set("SnacksDashboardTitle", { fg = p.magenta, bold = true })
      set("SnacksDashboardIcon", { fg = p.pink })
      set("SnacksDashboardKey", { fg = p.yellow, bold = true })
    end
    set("SnacksDashboardDesc", { fg = p.fg })
    set("SnacksDashboardFile", { fg = p.fg })
    set("SnacksDashboardDir", { fg = p.fg_dim })
    set("SnacksDashboardFooter", { fg = p.fg_dim, italic = true })
    set("SnacksDashboardSpecial", { fg = p.purple })

    Snacks.toggle.new({
      id = "ufo",
      name = "Enable/Disable ufo",
      get = function()
        return require("ufo").inspect()
      end,
      set = function(state)
        if state == nil then
          require("noice").enable()
          require("ufo").enable()
          vim.o.foldenable = true
          vim.o.foldcolumn = "1"
        else
          require("noice").disable()
          require("ufo").disable()
          vim.o.foldenable = false
          vim.o.foldcolumn = "0"
        end
      end,
    })
  end,
}

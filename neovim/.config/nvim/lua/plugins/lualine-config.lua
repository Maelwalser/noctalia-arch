-- Status line (cyberpunk palette)
return {
  'nvim-lualine/lualine.nvim',
  event = "UiEnter",
  dependencies = {
    { 'nvim-tree/nvim-web-devicons',    lazy = true },
    { 'linrongbin16/lsp-progress.nvim', lazy = true },
  },

  config = function()
    local lualine = require('lualine')
    local p = require('config.palette')

    local config = {
      options = {
        component_separators = '',
        section_separators = '',
        theme = {
          normal   = { c = { fg = p.fg, bg = p.bg } },
          inactive = { c = { fg = p.fg_dim, bg = p.bg } },
        },
      },
      refresh = {
        statusline = 1000,
        tabline = 1000,
        winbar = 1000
      },
      sections = {
        lualine_a = {},
        lualine_b = {},
        lualine_y = {},
        lualine_z = {},
        lualine_c = {},
        lualine_x = {},
      },
      inactive_sections = {
        lualine_a = {},
        lualine_b = {},
        lualine_y = {},
        lualine_z = {},
        lualine_c = {},
        lualine_x = {},
      },
    }

    local conditions = {
      buffer_not_empty = function()
        return vim.fn.empty(vim.fn.expand('%:t')) ~= 1
      end,
      hide_in_width = function()
        return vim.fn.winwidth(0) > 80
      end,
      check_git_workspace = function()
        local filepath = vim.fn.expand('%:p:h')
        local gitdir = vim.fn.finddir('.git', filepath .. ';')
        return gitdir and #gitdir > 0 and #gitdir < #filepath
      end,
    }

    local function ins_left(component)
      table.insert(config.sections.lualine_c, component)
    end

    local function ins_right(component)
      table.insert(config.sections.lualine_x, component)
    end

    ins_left {
      function()
        return '▊'
      end,
      color = { fg = p.cyan },
      padding = { left = 0, right = 1 },
    }

    ins_left {
      function()
        return ''
      end,
      color = function()
        local mode_color = {
          n      = p.cyan,
          i      = p.green,
          v      = p.magenta,
          [''] = p.magenta,
          V      = p.magenta,
          c      = p.pink,
          no     = p.red,
          s      = p.orange,
          S      = p.orange,
          [''] = p.orange,
          ic     = p.yellow,
          R      = p.purple,
          Rv     = p.purple,
          cv     = p.red,
          ce     = p.red,
          r      = p.cyan,
          rm     = p.cyan,
          ['r?'] = p.cyan,
          ['!']  = p.red,
          t      = p.orange,
        }
        return { fg = mode_color[vim.fn.mode()] or p.cyan }
      end,
      padding = { right = 1 },
    }

    ins_left {
      'filesize',
      cond = conditions.buffer_not_empty,
      color = { fg = p.fg_dim },
    }

    ins_left {
      'filename',
      cond = conditions.buffer_not_empty,
      color = { fg = p.magenta, gui = 'bold' },
    }

    ins_left { 'location', color = { fg = p.fg_dim } }

    ins_left { 'progress', color = { fg = p.fg, gui = 'bold' } }

    ins_left {
      'diagnostics',
      sources = { 'nvim_diagnostic' },
      symbols = { error = ' ', warn = ' ', info = ' ', hint = '󰌶 ' },
      diagnostics_color = {
        error = { fg = p.red },
        warn  = { fg = p.yellow },
        info  = { fg = p.cyan },
        hint  = { fg = p.purple },
      },
    }

    ins_left {
      function()
        return '%='
      end,
    }

    ins_left {
      function()
        local msg = 'No Active Lsp'
        local buf_ft = vim.api.nvim_get_option_value('filetype', { buf = 0 })
        local clients = vim.lsp.get_clients()
        if next(clients) == nil then
          return msg
        end
        for _, client in ipairs(clients) do
          local filetypes = client.config.filetypes
          if filetypes and vim.fn.index(filetypes, buf_ft) ~= -1 then
            return client.name
          end
        end
        return msg
      end,
      icon = ' LSP:',
      color = { fg = p.fg, gui = 'bold' },
    }

    ins_right {
      'o:encoding',
      fmt = string.upper,
      cond = conditions.hide_in_width,
      color = { fg = p.green, gui = 'bold' },
    }

    ins_right {
      'fileformat',
      fmt = string.upper,
      icons_enabled = false,
      color = { fg = p.green, gui = 'bold' },
    }

    ins_right {
      'branch',
      icon = '',
      color = { fg = p.magenta, gui = 'bold' },
    }

    ins_right {
      'diff',
      symbols = { added = ' ', modified = '󰝤 ', removed = ' ' },
      diff_color = {
        added    = { fg = p.green },
        modified = { fg = p.orange },
        removed  = { fg = p.red },
      },
      cond = conditions.hide_in_width,
    }

    ins_right {
      function()
        return '▊'
      end,
      color = { fg = p.cyan },
      padding = { left = 1 },
    }

    lualine.setup(config)
  end
}

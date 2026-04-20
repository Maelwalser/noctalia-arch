-- Colorscheme: tokyonight (night) as the base, re-colored with our
-- Nordic-cyberpunk palette via `on_colors`. We keep `on_highlights` small
-- and targeted — most syntax groups inherit tokyonight's excellent defaults
-- (now tinted by our palette). The overrides below exist only to:
--   • establish the function=blue / type=yellow / keyword=purple triad
--   • quiet down punctuation, comments, parameters
--   • keep diagnostics, selection, and indent guides consistent across plugins
--
-- Filename kept for lazy.nvim spec continuity.
return {
  "folke/tokyonight.nvim",
  name = "tokyonight",
  priority = 1000,
  lazy = false,
  config = function()
    local p = require("config.palette")

    require("tokyonight").setup({
      style = "night",
      transparent = false,
      terminal_colors = true,
      styles = {
        comments  = { italic = true },
        keywords  = { italic = true },
        functions = {},
        variables = {},
        sidebars  = "dark",
        floats    = "dark",
      },
      on_colors = function(c)
        -- Backgrounds / surfaces
        c.bg              = p.bg
        c.bg_dark         = p.bg_dim
        c.bg_float        = p.bg_float
        c.bg_popup        = p.bg_alt
        c.bg_sidebar      = p.bg_dim
        c.bg_statusline   = p.bg
        c.bg_visual       = p.visual
        c.bg_highlight    = p.cursorline
        c.border          = p.border
        c.border_highlight = p.cyan

        -- Foregrounds
        c.fg              = p.fg
        c.fg_dark         = p.fg_dim
        c.fg_gutter       = p.fg_dim
        c.comment         = p.comment

        -- Accents — tokyonight generates most highlight groups from these.
        c.blue            = p.blue
        c.blue0           = p.blue
        c.blue1           = p.blue
        c.blue2           = p.blue
        c.blue5           = p.cyan
        c.blue6           = p.teal
        c.blue7           = p.fg_dim
        c.cyan            = p.cyan
        c.teal            = p.teal
        c.green           = p.green
        c.green1          = p.green
        c.green2          = p.green
        c.yellow          = p.yellow
        c.orange          = p.orange
        c.red             = p.red
        c.red1            = p.red
        c.purple          = p.purple
        c.magenta         = p.magenta
        c.magenta2        = p.magenta
      end,
      on_highlights = function(hl, _)
        -- ---------- Core UI ----------
        hl.Normal       = { fg = p.fg, bg = p.bg }
        hl.NormalNC     = { fg = p.fg, bg = p.bg }
        hl.NormalFloat  = { fg = p.fg, bg = p.bg_float }
        hl.FloatBorder  = { fg = p.border, bg = p.bg_float }
        hl.FloatTitle   = { fg = p.blue, bg = p.bg_float, bold = true }
        hl.WinSeparator = { fg = p.border, bg = "NONE" }
        hl.VertSplit    = { fg = p.border, bg = "NONE" }
        hl.SignColumn   = { bg = "NONE" }
        hl.FoldColumn   = { bg = "NONE", fg = p.fg_dim }
        hl.EndOfBuffer  = { fg = p.bg, bg = p.bg }
        hl.StatusLine   = { fg = p.fg, bg = p.bg }
        hl.StatusLineNC = { fg = p.fg_dim, bg = p.bg }

        -- ---------- Cursor / line numbers ----------
        hl.CursorLine   = { bg = p.cursorline }
        hl.CursorLineNr = { fg = p.yellow, bold = true }
        hl.LineNr       = { fg = p.fg_dim }
        hl.LineNrAbove  = { fg = p.fg_dim }
        hl.LineNrBelow  = { fg = p.fg_dim }
        hl.Cursor       = { fg = p.bg, bg = p.fg }
        hl.TermCursor   = { fg = p.bg, bg = p.fg }

        -- ---------- Selection / search ----------
        hl.Visual    = { bg = p.visual }
        hl.VisualNOS = { bg = p.visual }
        hl.Search    = { fg = p.bg, bg = p.yellow, bold = true }
        hl.IncSearch = { fg = p.bg, bg = p.orange, bold = true }
        hl.CurSearch = { fg = p.bg, bg = p.orange, bold = true }
        hl.MatchParen = { fg = p.cyan, bold = true, underline = true }

        -- ---------- Popup menu ----------
        hl.Pmenu    = { fg = p.fg, bg = p.bg_alt }
        hl.PmenuSel = { fg = p.fg, bg = p.selection, bold = true }
        hl.PmenuSbar = { bg = p.bg_alt }
        hl.PmenuThumb = { bg = p.border }

        -- ---------- Diagnostics ----------
        hl.DiagnosticError = { fg = p.red }
        hl.DiagnosticWarn  = { fg = p.yellow }
        hl.DiagnosticInfo  = { fg = p.blue }
        hl.DiagnosticHint  = { fg = p.teal }
        hl.DiagnosticOk    = { fg = p.green }
        hl.DiagnosticVirtualTextError = { fg = p.red, bg = "NONE" }
        hl.DiagnosticVirtualTextWarn  = { fg = p.yellow, bg = "NONE" }
        hl.DiagnosticVirtualTextInfo  = { fg = p.blue, bg = "NONE" }
        hl.DiagnosticVirtualTextHint  = { fg = p.teal, bg = "NONE" }
        hl.DiagnosticUnderlineError = { sp = p.red, undercurl = true }
        hl.DiagnosticUnderlineWarn  = { sp = p.yellow, undercurl = true }
        hl.DiagnosticUnderlineInfo  = { sp = p.blue, undercurl = true }
        hl.DiagnosticUnderlineHint  = { sp = p.teal, undercurl = true }

        -- ---------- Git signs / diff ----------
        hl.GitSignsAdd    = { fg = p.green, bg = "NONE" }
        hl.GitSignsChange = { fg = p.orange, bg = "NONE" }
        hl.GitSignsDelete = { fg = p.red, bg = "NONE" }
        hl.DiffAdd    = { fg = p.green, bg = "NONE" }
        hl.DiffChange = { fg = p.orange, bg = "NONE" }
        hl.DiffDelete = { fg = p.red, bg = "NONE" }

        -- ---------- Syntax hierarchy ----------
        -- Core philosophy: THREE dominant hues (function/type/keyword)
        -- so your eye immediately separates "verb" from "noun" from
        -- "structure". Everything else fades back.

        -- Keywords = muted purple italic (structural verbs)
        hl.Keyword                = { fg = p.purple, italic = true }
        hl.Conditional            = { fg = p.purple, italic = true }
        hl.Repeat                 = { fg = p.purple, italic = true }
        hl.Statement              = { fg = p.purple, italic = true }
        hl.Operator               = { fg = p.cyan }
        hl["@keyword"]            = { fg = p.purple, italic = true }
        hl["@keyword.function"]   = { fg = p.purple, italic = true }
        hl["@keyword.return"]     = { fg = p.magenta, italic = true }
        hl["@keyword.operator"]   = { fg = p.purple }
        hl["@keyword.conditional"] = { fg = p.purple, italic = true }
        hl["@keyword.repeat"]     = { fg = p.purple, italic = true }
        hl["@keyword.import"]     = { fg = p.cyan }
        hl["@keyword.modifier"]   = { fg = p.purple, italic = true }
        hl["@keyword.coroutine"]  = { fg = p.purple, italic = true }
        hl["@keyword.exception"]  = { fg = p.pink, italic = true }
        hl.Exception              = { fg = p.pink, italic = true }

        -- Functions = soft blue (the "who does what" axis)
        hl.Function               = { fg = p.blue }
        hl["@function"]           = { fg = p.blue }
        hl["@function.call"]      = { fg = p.blue }
        hl["@function.method"]    = { fg = p.blue }
        hl["@function.method.call"] = { fg = p.blue }
        hl["@function.builtin"]   = { fg = p.blue, italic = true }
        hl["@function.macro"]     = { fg = p.blue, italic = true }
        hl["@constructor"]        = { fg = p.yellow }

        -- Types = warm yellow (the "what kind of thing" axis)
        hl.Type                   = { fg = p.yellow }
        hl.StorageClass           = { fg = p.purple, italic = true }
        hl.Structure              = { fg = p.yellow }
        hl.Typedef                = { fg = p.yellow }
        hl["@type"]               = { fg = p.yellow }
        hl["@type.builtin"]       = { fg = p.yellow, italic = true }
        hl["@type.definition"]    = { fg = p.yellow }
        hl["@type.qualifier"]     = { fg = p.purple, italic = true }

        -- Strings = calm green
        hl.String                 = { fg = p.green }
        hl.Character              = { fg = p.green }
        hl["@string"]             = { fg = p.green }
        hl["@string.escape"]      = { fg = p.pink }
        hl["@string.special"]     = { fg = p.orange }
        hl["@string.regexp"]      = { fg = p.pink }

        -- Numbers, booleans, constants = warm orange
        hl.Number                 = { fg = p.orange }
        hl.Float                  = { fg = p.orange }
        hl.Boolean                = { fg = p.orange }
        hl.Constant               = { fg = p.orange }
        hl["@number"]             = { fg = p.orange }
        hl["@boolean"]            = { fg = p.orange }
        hl["@constant"]           = { fg = p.orange }
        hl["@constant.builtin"]   = { fg = p.orange, italic = true }
        hl["@constant.macro"]     = { fg = p.orange }

        -- Variables / parameters / fields
        hl.Identifier             = { fg = p.fg }
        hl["@variable"]           = { fg = p.fg }
        hl["@variable.builtin"]   = { fg = p.pink, italic = true }
        hl["@variable.parameter"] = { fg = p.fg, italic = true }
        hl["@variable.member"]    = { fg = p.cyan }
        hl["@property"]           = { fg = p.cyan }
        hl["@field"]              = { fg = p.cyan }

        -- Comments = faded italic, secondary by design (~3:1 contrast)
        hl.Comment                = { fg = p.comment, italic = true }
        hl["@comment"]            = { fg = p.comment, italic = true }
        hl["@comment.documentation"] = { fg = p.comment, italic = true }
        hl["@comment.todo"]       = { fg = p.bg, bg = p.yellow, bold = true }
        hl["@comment.note"]       = { fg = p.bg, bg = p.blue, bold = true }
        hl["@comment.warning"]    = { fg = p.bg, bg = p.orange, bold = true }
        hl["@comment.error"]      = { fg = p.fg, bg = p.red, bold = true }

        -- Punctuation = faded so content pops
        hl.Delimiter              = { fg = p.fg }
        hl["@punctuation"]        = { fg = p.fg_dim }
        hl["@punctuation.bracket"] = { fg = p.fg_dim }
        hl["@punctuation.delimiter"] = { fg = p.fg_dim }
        hl["@punctuation.special"] = { fg = p.cyan }
        hl["@operator"]           = { fg = p.cyan }

        -- Preproc / includes / macros
        hl.PreProc                = { fg = p.magenta }
        hl.Include                = { fg = p.cyan }
        hl.Define                 = { fg = p.magenta }
        hl.Macro                  = { fg = p.magenta }
        hl.Special                = { fg = p.pink }
        hl.SpecialChar            = { fg = p.pink }
        hl.Title                  = { fg = p.blue, bold = true }

        -- ---------- LSP semantic tokens ----------
        hl["@lsp.type.class"]      = { fg = p.yellow }
        hl["@lsp.type.interface"]  = { fg = p.yellow, italic = true }
        hl["@lsp.type.enum"]       = { fg = p.yellow }
        hl["@lsp.type.enumMember"] = { fg = p.orange }
        hl["@lsp.type.struct"]     = { fg = p.yellow }
        hl["@lsp.type.parameter"]  = { fg = p.fg, italic = true }
        hl["@lsp.type.property"]   = { fg = p.cyan }
        hl["@lsp.type.variable"]   = { fg = p.fg }
        hl["@lsp.type.namespace"]  = { fg = p.magenta }
        hl["@lsp.type.function"]   = { fg = p.blue }
        hl["@lsp.type.method"]     = { fg = p.blue }
        hl["@lsp.type.macro"]      = { fg = p.magenta }
        hl["@lsp.type.decorator"]  = { fg = p.cyan, italic = true }
        hl["@lsp.mod.deprecated"]  = { strikethrough = true, fg = p.fg_dim }
        hl["@lsp.mod.readonly"]    = { italic = true }

        -- ---------- Markdown / tags ----------
        hl["@tag"]              = { fg = p.purple }
        hl["@tag.attribute"]    = { fg = p.cyan, italic = true }
        hl["@tag.delimiter"]    = { fg = p.fg_dim }
        hl["@markup.heading"]   = { fg = p.blue, bold = true }
        hl["@markup.heading.1"] = { fg = p.blue, bold = true }
        hl["@markup.heading.2"] = { fg = p.cyan, bold = true }
        hl["@markup.heading.3"] = { fg = p.yellow, bold = true }
        hl["@markup.heading.4"] = { fg = p.green, bold = true }
        hl["@markup.strong"]    = { fg = p.fg, bold = true }
        hl["@markup.italic"]    = { fg = p.fg, italic = true }
        hl["@markup.link"]      = { fg = p.cyan, underline = true }
        hl["@markup.link.url"]  = { fg = p.cyan, underline = true }
        hl["@markup.raw"]       = { fg = p.green, bg = p.bg_alt }
        hl["@markup.list"]      = { fg = p.cyan }
        hl["@markup.quote"]     = { fg = p.fg_dim, italic = true }

        -- ---------- Integrations (palette-consistent) ----------
        -- Indent-blankline
        hl.IblIndent     = { fg = p.indent, nocombine = true }
        hl.IblWhitespace = { fg = p.indent, nocombine = true }
        hl.IblScope      = { fg = p.cyan, nocombine = true }

        -- Oil
        hl.OilDir     = { fg = p.cyan, bold = true }
        hl.OilDirIcon = { fg = p.cyan, bold = true }
        hl.OilFile    = { fg = p.fg }

        -- Trouble
        hl.TroubleNormal = { fg = p.fg, bg = p.bg_alt }
        hl.TroubleText   = { fg = p.fg }
        hl.TroubleCount  = { fg = p.orange, bg = p.bg_alt }

        -- LSP document-highlight groups: disabled (no-op) so any lingering
        -- reference highlights from previous sessions render invisibly
        hl.LspReferenceText  = {}
        hl.LspReferenceRead  = {}
        hl.LspReferenceWrite = {}
      end,
    })

    vim.cmd("colorscheme tokyonight-night")
  end,
}

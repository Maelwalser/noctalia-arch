return {
    "hrsh7th/nvim-cmp",
    event = "InsertEnter",
    dependencies = {
        "onsails/lspkind.nvim",
        {
            "L3MON4D3/LuaSnip",
            build = "make install_jsregexp",
            dependencies = { "rafamadriz/friendly-snippets" },
        },
        "saadparwaiz1/cmp_luasnip",
        "hrsh7th/cmp-nvim-lsp",
        "hrsh7th/cmp-buffer",
        "hrsh7th/cmp-path",
        "hrsh7th/cmp-cmdline",
    },
    config = function()
        local cmp = require("cmp")
        local luasnip = require("luasnip")
        local lspkind = require("lspkind")

        -- This loads vscode-style snippets, which is a superset of friendly-snippets
        require("luasnip.loaders.from_vscode").lazy_load()

        local has_words_before = function()
            local line, col = unpack(vim.api.nvim_win_get_cursor(0))
            return col ~= 0 and vim.api.nvim_buf_get_lines(0, line - 1, line, true)[1]:sub(col, col):match("%s") == nil
        end

        cmp.setup({
            snippet = {
                expand = function(args)
                    luasnip.lsp_expand(args.body)
                end,
            },
            formatting = {
                format = lspkind.cmp_format({
                    mode = "symbol_text",
                    maxwidth = 50,
                    ellipsis_char = "...",
                }),
            },
            mapping = cmp.mapping.preset.insert({
                -- Navigation with Ctrl+j/k
                ["<C-j>"] = cmp.mapping.select_next_item({ behavior = cmp.SelectBehavior.Select }),
                ["<C-k>"] = cmp.mapping.select_prev_item({ behavior = cmp.SelectBehavior.Select }),

                -- Alternative navigation with Ctrl+n/p (keep as backup)
                ["<C-n>"] = cmp.mapping.select_next_item({ behavior = cmp.SelectBehavior.Insert }),
                ["<C-p>"] = cmp.mapping.select_prev_item({ behavior = cmp.SelectBehavior.Insert }),

                -- Scroll documentation window
                ["<C-d>"] = cmp.mapping.scroll_docs(-4),
                ["<C-f>"] = cmp.mapping.scroll_docs(4),

                -- Trigger completion manually
                ["<C-Space>"] = cmp.mapping.complete(),

                -- Abort completion
                ["<C-e>"] = cmp.mapping.abort(),

                -- Confirm selection
                ["<CR>"] = cmp.mapping.confirm({ select = true }),

                -- Tab - jump to next snippet placeholder (no cmp navigation)
                ["<Tab>"] = cmp.mapping(function(fallback)
                    if luasnip.expand_or_jumpable() then
                        luasnip.expand_or_jump()
                    else
                        fallback()
                    end
                end, { "i", "s" }),

                -- Shift-Tab - reserved for Minuet AI completion (fallback to snippet jump)
                ["<S-Tab>"] = cmp.mapping(function(fallback)
                    if luasnip.jumpable(-1) then
                        luasnip.jump(-1)
                    else
                        fallback() -- This allows Minuet AI to handle Shift-Tab
                    end
                end, { "i", "s" }),
            }),
            sources = cmp.config.sources({
                { name = "nvim_lsp", priority = 1000 },
                { name = "luasnip",  priority = 750 },
                { name = "buffer",   priority = 500 },
                { name = "path",     priority = 250 },
            }),
            window = {
                completion = cmp.config.window.bordered({
                    winhighlight = "Normal:Pmenu,FloatBorder:Pmenu,Search:None",
                    col_offset = -3,
                    side_padding = 0,
                }),
                documentation = cmp.config.window.bordered(),
            },
            experimental = {
                ghost_text = true,
            },
        })

        -- Setup command line completion for '/'
        cmp.setup.cmdline('/', {
            mapping = cmp.mapping.preset.cmdline({
                ["<C-j>"] = { c = cmp.mapping.select_next_item() },
                ["<C-k>"] = { c = cmp.mapping.select_prev_item() },
                ["<S-Tab>"] = { c = cmp.mapping.confirm({ select = true }) },
            }),
            sources = {
                { name = 'buffer' }
            }
        })

        -- Setup command line completion for '?'
        cmp.setup.cmdline('?', {
            mapping = cmp.mapping.preset.cmdline({
                ["<C-j>"] = { c = cmp.mapping.select_next_item() },
                ["<C-k>"] = { c = cmp.mapping.select_prev_item() },
                ["<S-Tab>"] = { c = cmp.mapping.confirm({ select = true }) },
            }),
            sources = {
                { name = 'buffer' }
            }
        })

        -- Setup command line completion for ':'
        cmp.setup.cmdline(':', {
            mapping = cmp.mapping.preset.cmdline({
                ["<C-j>"] = { c = cmp.mapping.select_next_item() },
                ["<C-k>"] = { c = cmp.mapping.select_prev_item() },
                ["<S-Tab>"] = { c = cmp.mapping.confirm({ select = true }) },
            }),
            sources = cmp.config.sources({
                { name = 'path' }
            }, {
                { name = 'cmdline' }
            }),
            matching = { disallow_symbol_nonprefix_matching = false }
        })

        -- Set up floating windows for diagnostics globally.
        vim.diagnostic.config({
            signs = true,
            update_in_insert = false,
            underline = true,
            severity_sort = true,
            virtual_text = {
                spacing = 4,
                source = "if_many",
                prefix = "●",
            },
        })
    end,
}

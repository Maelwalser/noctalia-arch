return {
    "nvim-treesitter/nvim-treesitter",
    event = { "BufReadPost", "BufNewFile" },
    branch = "master",
    dependencies = {
        { 'nvim-treesitter/nvim-treesitter-textobjects', lazy = true },
        { "nvim-treesitter/nvim-treesitter-context",     lazy = true },
        { "windwp/nvim-ts-autotag",                      lazy = true }
    },
    build = ':TSUpdate',
    cmd = { "TSUpdateSync", "TSInstall", "TSUpdate", "TSBufEnable", "TSEnable" },
    config = function()
        local configs = require("nvim-treesitter.configs")
        configs.setup({

            ensure_installed = { "lua", "vim", "vimdoc", "java", "javascript", "typescript", "json", "html", "css", "markdown", "dockerfile", "git_rebase", "gitattributes", "gitcommit", "gitignore", "json5", "jsonc", "markdown_inline", "python", "regex", "tsx", "sql", "yaml", "vue", "go", "gomod", "gosum", "gowork", "c" },

            sync_install = true,

            auto_install = true,


            highlight = {
                enable = true,
                additional_vim_regex_highlighting = false,
            },

            indent = {
                enable = true
            },

            textobjects = {
                select = {
                    enable = true,
                    lookahead = true,
                },
                move = {
                    enable = true,
                    set_jumps = true,
                }
            }

        })
        require('nvim-treesitter.install').prefer_git = true

        -- Set up parser cache directory
        local cache_dir = vim.fn.stdpath("cache") .. "/treesitter"
        vim.fn.mkdir(cache_dir, "p")                                      -- Ensure directory exists
        require("nvim-treesitter.install").parser_install_dir = cache_dir -- Direct assignment
        vim.opt.runtimepath:append(cache_dir)
    end,
}

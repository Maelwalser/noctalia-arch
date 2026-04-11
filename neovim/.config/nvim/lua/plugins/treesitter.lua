return {
    "nvim-treesitter/nvim-treesitter",
    event = { "BufReadPost", "BufNewFile" },
    branch = "main",
    dependencies = {
        { 'nvim-treesitter/nvim-treesitter-textobjects', lazy = true },
        { "nvim-treesitter/nvim-treesitter-context",     lazy = true },
        { "windwp/nvim-ts-autotag",                      lazy = true }
    },
    build = ':TSUpdate',
    cmd = { "TSUpdateSync", "TSInstall", "TSUpdate", "TSBufEnable", "TSEnable" },
    config = function()
        require("nvim-treesitter.config").setup({})

        -- Install parsers that should always be present
        local ensure_installed = {
            "lua", "vim", "vimdoc", "java", "javascript", "typescript",
            "json", "html", "css", "markdown", "dockerfile", "git_rebase",
            "gitattributes", "gitcommit", "gitignore", "json5",
            "markdown_inline", "python", "regex", "tsx", "sql", "yaml",
            "vue", "go", "gomod", "gosum", "gowork", "c",
        }

        local installed = require("nvim-treesitter.config").get_installed()
        local installed_set = {}
        for _, lang in ipairs(installed) do
            installed_set[lang] = true
        end

        local to_install = vim.tbl_filter(function(lang)
            return not installed_set[lang]
        end, ensure_installed)

        if #to_install > 0 then
            require("nvim-treesitter.install").install(to_install)
        end
    end,
}

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

        local ensure_installed = {
            "bash", "c", "css", "diff", "dockerfile", "git_rebase",
            "gitattributes", "gitcommit", "gitignore", "go", "gomod",
            "gosum", "gowork", "html", "java", "javascript", "json",
            "json5", "lua", "luadoc", "make", "markdown",
            "markdown_inline", "printf", "python", "query", "regex",
            "ron", "rust", "sql", "toml", "tsx", "typescript", "vim",
            "vimdoc", "vue", "xml", "yaml",
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

        -- main branch of nvim-treesitter no longer auto-enables highlight;
        -- attach it per-buffer for the filetypes we ensure.
        vim.api.nvim_create_autocmd("FileType", {
            pattern = ensure_installed,
            callback = function(ev)
                pcall(vim.treesitter.start, ev.buf)
            end,
        })
    end,
}

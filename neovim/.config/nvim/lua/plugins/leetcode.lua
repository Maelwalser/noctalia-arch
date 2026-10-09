return {
    "kawre/leetcode.nvim",
    -- Full-screen app entered through `:Leet`. Loading it (and its plenary/nui
    -- dependencies) at startup bought nothing.
    cmd = "Leet",
    build = ":TSUpdate html",
    dependencies = {
        "nvim-lua/plenary.nvim",
        "MunifTanjim/nui.nvim",
    },
    opts = {
    },
}

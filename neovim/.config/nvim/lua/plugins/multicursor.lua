return {
    "smoka7/multicursors.nvim",
    dependencies = { 'nvimtools/hydra.nvim' },
    cmd = { 'MCstart', 'MCvisual', 'MCclear', 'MCpattern', 'MCvisualPattern', 'MCunderCursor' },
    keys = {
        {
            mode = { 'v', 'n' },
            '<Leader>m',
            '<cmd>MCstart<cr>',
            desc = 'Create multi-cursor selection',
        },
    },
    opts = {},
}

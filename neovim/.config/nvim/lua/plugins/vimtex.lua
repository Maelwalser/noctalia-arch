return {
    'KeitaNakamura/tex-conceal.vim',
    config = function()
        vim.g.tex_superscripts = "[0-9a-zA-W.,:;+-<>/()=]"
        vim.g.tex_subscripts = "[0-9aehijklmnoprstuvx,+-/().]"
        vim.g.tex_conceal_frac = 1
        vim.o.conceallevel = 2
        vim.g.tex_conceal = "abdgm"
    end,

}

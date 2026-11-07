vim.opt.wrap = true -- Wrap text
vim.opt.breakindent = true -- Match indent on line break
vim.opt.linebreak = true -- Line break on whole words

-- j/k move by screen line over wrapped text, in Visual mode as well so a
-- selection grows row by row instead of jumping a whole paragraph.
vim.keymap.set({ "n", "x" }, "j", "gj", { buffer = true })
vim.keymap.set({ "n", "x" }, "k", "gk", { buffer = true })

-- Spell check
vim.opt.spelllang = 'en_us'
vim.opt.spell = true

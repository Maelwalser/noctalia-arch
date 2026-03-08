nmap j gj
nmap k gk

set clipboard=unnamedplus
imap <C-c> <Esc>

unmap <Space>

" Save Files
nmap <Space>ww :w<CR>

" Search For Files (Quick Switcher)
exmap SearchFiles obcommand switcher:open
nmap <Space>ff :SearchFiles<CR>

" Split Vertically
exmap SplitVert obcommand workspace:split-vertical
nmap <Space>wv :SplitVert<CR>

" Split Horizontally
exmap SplitHoriz obcommand workspace:split-horizontal
nmap <Space>wh :SplitHoriz<CR>

" Window navigation
exmap FocusLeft obcommand editor:focus-left
nmap <C-h> :FocusLeft<CR>

exmap FocusDown obcommand editor:focus-bottom
nmap <C-j> :FocusDown<CR>

exmap FocusUp obcommand editor:focus-top
nmap <C-k> :FocusUp<CR>

exmap FocusRight obcommand editor:focus-right
nmap <C-l> :FocusRight<CR>


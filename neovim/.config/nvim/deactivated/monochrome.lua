return {
 'kdheepak/monochrome.nvim',
  name = "monochrome",
  lazy = false,
  priority = 1000,
  config = function()
    vim.cmd.colorscheme "monochrome"
  end
}

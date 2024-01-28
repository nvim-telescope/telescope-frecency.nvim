if not vim.env.PLENARY_PATH then
  error "set $PLENARY_PATH to find plenary.nvim"
end
if not vim.env.TELESCOPE_PATH then
  error "set $TELESCOPE_PATH to find telescope.nvim"
end
vim.opt.runtimepath:append(vim.env.PLENARY_PATH)
vim.opt.runtimepath:append(vim.env.TELESCOPE_PATH)
vim.cmd.runtime "plugin/plenary.vim"

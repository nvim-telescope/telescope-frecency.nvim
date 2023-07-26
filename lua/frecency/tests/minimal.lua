if not vim.env.PLENARY_PATH then
  error "set $PLENARY_PATH to find plenary.nvim"
end
vim.opt.runtimepath:append "."
vim.opt.runtimepath:append(vim.env.PLENARY_PATH)
vim.cmd.runtime "plugin/plenary.vim"

if not vim.env.PLENTEST_PATH then
  error "set $PLENTEST_PATH to find plentest.nvim"
end
if not vim.env.TELESCOPE_PATH then
  error "set $TELESCOPE_PATH to find telescope.nvim"
end
vim.opt.runtimepath:append(vim.env.PLENTEST_PATH)
vim.opt.runtimepath:append(vim.env.TELESCOPE_PATH)
vim.opt.runtimepath:append "."
vim.cmd.runtime { "plugin/telescope", bang = true }

local telescope = (function()
  local ok, m = pcall(require, "telescope")
  if not ok then
    error "telescope-frecency: couldn't find telescope.nvim, please install"
  end
  return m
end)()
local M = {}

local db = require "frecency.db"
local picker = require "frecency.picker"

M.setup = function(ext_config)
  db.set_config(ext_config)
  picker.setup(db, ext_config)
  -- TODO: perhaps ignore buffer without file path here?
  vim.cmd [[
  augroup TelescopeFrecency
    autocmd!
    autocmd BufWinEnter,BufWritePost * lua require'frecency.db'.register()
  augroup END
  ]]
end

M.health = function()
  if ({ pcall(require, "sql") })[1] then
    vim.fn["health#report_ok"] "sql.nvim installed."
  else
    vim.fn["health#report_error"] "sql.nvim is required for telescope-frecency.nvim to work."
  end
end

M.exports = {
  frecency = picker.fd,
  get_workspace_tags = picker.workspace_tags, --TODO: what is the use case for this?
  validate_db = db.validate,
}

return telescope.register_extension(M)

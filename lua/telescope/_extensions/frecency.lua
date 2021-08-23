local telescope = (function()
  local ok, m = pcall(require, "telescope")
  if not ok then
    error "telescope-frecency: couldn't find telescope.nvim, please install"
  end
  return m
end)()

local p = {}
local db = require "frecency.db"
local picker = require "frecency.picker"

p.setup = function(ext_config)
  picker.setup(db, ext_config)
  vim.cmd [[
    augroup TelescopeFrecency
      autocmd!
      autocmd BufWinEnter,BufWritePost * lua require'frecency.db'.register()
    augroup END
  ]]
end

p.exports = {
  frecency = picker.fd,
  get_workspace_tags = picker.workspace_tags, --TODO: what is the use case for this?
  validate_db = db.validate,
  health = function() -- TODO: are we using that, where ?
    local has_sql, _ = pcall(require, "sql")
    if has_sql then
      vim.fn["health#report_ok"] "sql.nvim installed."
    else
      vim.fn["health#report_error"] "NOOO"
    end
  end,
}

return telescope.register_extension(p)

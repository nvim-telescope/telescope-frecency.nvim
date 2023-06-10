local telescope = (function()
  local ok, m = pcall(require, "telescope")
  if not ok then
    error "telescope-frecency: couldn't find telescope.nvim, please install"
  end
  return m
end)()

local picker = require "frecency.picker"

return telescope.register_extension {
  setup = picker.setup,
  health = function()
    if ({ pcall(require, "sqlite") })[1] then
      vim.health.report_ok "sql.nvim installed."
    else
      vim.health.report_error "sql.nvim is required for telescope-frecency.nvim to work."
    end
    if ({ pcall(require, "nvim-web-devicons") })[1] then
      vim.health.report_ok "nvim-web-devicons installed."
    else
      vim.health.report_info "nvim-web-devicons is not installed."
    end
  end,
  exports = {
    frecency = picker.fd,
    complete = picker.complete,
  },
}

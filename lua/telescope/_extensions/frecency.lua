local frecency = require "frecency"
local sqlite = require "frecency.sqlite"

return require("telescope").register_extension {
  setup = frecency.setup,
  health = function()
    if sqlite.can_use then
      vim.health.ok "sqlite.lua installed."
    else
      vim.health.info "sqlite.lua is required when use_sqlite = true"
    end
    if vim.F.npcall(require, "nvim-web-devicons") then
      vim.health.ok "nvim-web-devicons installed."
    else
      vim.health.info "nvim-web-devicons is not installed."
    end
  end,
  exports = {
    frecency = frecency.start,
    complete = frecency.complete,
  },
}

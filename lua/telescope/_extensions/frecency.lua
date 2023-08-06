local frecency = require "frecency"

return require("telescope").register_extension {
  setup = frecency.setup,
  health = function()
    if vim.F.npcall(require, "sqlite") then
      vim.health.ok "sqlite.lua installed."
    else
      vim.health.error "sqlite.lua is required for telescope-frecency.nvim to work."
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

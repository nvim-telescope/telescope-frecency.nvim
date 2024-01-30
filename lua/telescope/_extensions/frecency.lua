local frecency = require "frecency"

return require("telescope").register_extension {
  setup = frecency.setup,
  health = function()
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

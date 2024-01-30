local frecency = require "frecency"

return require("telescope").register_extension {
  setup = frecency.setup,
  health = function()
    if vim.F.npcall(require, "nvim-web-devicons") then
      vim.health.ok "nvim-web-devicons installed."
    else
      vim.health.info "nvim-web-devicons is not installed."
    end
    if vim.fn.executable "rg" == 1 then
      vim.health.ok "ripgrep installed."
    elseif vim.fn.executable "fdfind" == 1 then
      vim.health.ok "fdfind installed."
    elseif vim.fn.executable "fd" == 1 then
      vim.health.ok "fd installed."
    else
      vim.health.info "No suitable find executable found."
    end
  end,
  exports = {
    frecency = frecency.start,
    complete = frecency.complete,
  },
}

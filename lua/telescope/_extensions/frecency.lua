local frecency = require "frecency"

return require("telescope").register_extension {
  exports = {
    frecency = frecency.start,
    complete = frecency.complete,
    query = frecency.query,
  },
  setup = frecency.setup,
  health = function()
    if vim.fn.has "nvim-0.10" == 1 then
      vim.health.ok "Neovim version is 0.10 or higher."
    else
      vim.health.error "Neovim version must be 0.10 or higher."
    end
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
}

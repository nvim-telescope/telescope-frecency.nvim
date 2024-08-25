local config = require "frecency.config"
local log = require "frecency.log"

---@class FrecencyTimer
---@field has_lazy boolean?
local M = {}

---@param event string
---@return nil
function M.track(event)
  if not config.debug then
    return
  elseif M.has_lazy == nil then
    M.has_lazy = (pcall(require, "lazy.stats"))
    if not M.has_lazy then
      log.debug "frecency.timer needs lazy.nvim"
    end
  end
  if M.has_lazy then
    require("lazy.stats").track("[telescope-frecency] " .. event)
  end
end

return M

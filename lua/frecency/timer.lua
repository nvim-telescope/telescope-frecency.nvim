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
    local stats = require "lazy.stats"
    ---@param n integer
    ---@return string
    local function make_key(n)
      return ("[telescope-frecency] %s: %d"):format(event, n)
    end
    local key
    local num = 0
    while true do
      key = make_key(num)
      if not stats._stats.times[key] then
        break
      end
      num = num + 1
    end
    stats.track(key)
  end
end

return M

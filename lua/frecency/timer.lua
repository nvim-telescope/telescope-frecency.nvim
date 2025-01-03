local config = require "frecency.config"
local log = require "frecency.log"

---@class FrecencyTimer
---@field has_lazy? boolean
---@field has_func_err? boolean
local M = {}

---@param event string
---@return nil
function M.track(event)
  if not config.debug then
    return
  end
  local debug_timer = config.debug_timer
  if type(debug_timer) == "function" and not M.has_func_err then
    local ok, err = pcall(debug_timer, event)
    if not ok then
      log.warn(("config.debug_timer has error: %s"):format(err))
      M.has_func_err = true
    end
    return
  elseif M.has_lazy == nil then
    M.has_lazy = (pcall(require, "lazy.stats"))
    if not M.has_lazy then
      log.debug "frecency.timer needs lazy.nvim"
    end
  end
  if M.has_lazy then
    local stats = require "lazy.stats"
    local function make_key(num)
      local key = num and ("[telescope-frecency] %s: %d"):format(event, num) or "[telescope-frecency] " .. event
      return stats._stats.times[key] and make_key((num or 1) + 1) or key
    end
    stats.track(make_key())
    if debug_timer then
      log.debug(event)
    end
  end
end

---@return string
function M.pp()
  local times = require("lazy.stats")._stats.times
  local result = vim
    .iter(times)
    :map(function(event, t)
      return { event = event, t = t }
    end)
    :totable()
  table.sort(result, function(a, b)
    return a.t < b.t
  end)
  return table.concat(
    vim
      .iter(result)
      :map(function(r)
        return ("%8.3f : %s"):format(r.t, r.event)
      end)
      :totable(),
    "\n"
  )
end

return M

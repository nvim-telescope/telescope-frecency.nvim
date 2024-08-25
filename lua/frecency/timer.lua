local config = require "frecency.config"
local log = require "frecency.log"
local uv = vim.uv or vim.loop

---@class FrecencyTimer
---@field elapsed number
---@field start integer
---@field title string
local Timer = {}

---@param title string
---@return FrecencyTimer
Timer.new = function(title)
  return setmetatable({ start = uv.hrtime(), title = title }, { __index = Timer })
end

---@return nil
function Timer:finish()
  if not config.debug then
    return
  end
  self.elapsed = (uv.hrtime() - self.start) / 1000000000
  log.debug(("[%s] takes %.3f seconds"):format(self.title, self.elapsed))
end

return Timer

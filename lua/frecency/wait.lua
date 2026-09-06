local async = require "frecency.async"

---@class FrecencyWait
---@field config FrecencyWaitConfig
local Wait = {}

---@class FrecencyWaitConfig
---@field time integer default: 5000

---@alias FrecencyWaitCallback fun(): nil

---@param f FrecencyWaitCallback
---@param opts FrecencyWaitConfig?
Wait.new = function(f, opts)
  return setmetatable({ f = f, config = vim.tbl_extend("force", { time = 5000 }, opts or {}) }, { __index = Wait })
end

---@async
---@private
Wait.f = function()
  error "implement me"
end

---@return boolean ok
---@return any? err `"timeout"` when the call did not finish in time
function Wait:run()
  return async.run(self.f):pwait(self.config.time)
end

---@param f FrecencyWaitCallback
---@param opts FrecencyWaitConfig?
---@return boolean ok
---@return any? err
return function(f, opts)
  return Wait.new(f, opts):run()
end

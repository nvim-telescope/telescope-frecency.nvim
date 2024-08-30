local async = require "plenary.async"

---@class FrecencyWait
---@field config FrecencyWaitConfig
local Wait = {}

---@class FrecencyWaitConfig
---@field time integer default: 5000
---@field interval integer default: 200

---@alias FrecencyWaitCallback fun(): nil

---@param f FrecencyWaitCallback
---@param opts FrecencyWaitConfig?
Wait.new = function(f, opts)
  return setmetatable(
    { f = f, config = vim.tbl_extend("force", { time = 5000, interval = 200 }, opts or {}) },
    { __index = Wait }
  )
end

---@async
---@private
Wait.f = function()
  error "implement me"
end

---@return boolean ok
---@return nil|-1|-2 status
function Wait:run()
  local done = false
  async.void(function()
    self.f()
    done = true
  end)()
  return vim.wait(self.config.time, function()
    return done
  end, self.config.interval)
end

---@param f FrecencyWaitCallback
---@param opts FrecencyWaitConfig?
---@return boolean ok
---@return nil|-1|-2 status
return function(f, opts)
  return Wait.new(f, opts):run()
end

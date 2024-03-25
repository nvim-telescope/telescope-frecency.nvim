---@class FrecencyState
---@field picker? FrecencyTelescopePicker
local State = {}

---@return FrecencyState
State.new = function()
  return setmetatable({}, { __index = State, __meta = "kv" })
end

---@param picker? FrecencyTelescopePicker
---@return nil
function State:set(picker)
  self.picker = picker
end

---@return FrecencyTelescopePicker?
function State:get()
  return self.picker
end

return State

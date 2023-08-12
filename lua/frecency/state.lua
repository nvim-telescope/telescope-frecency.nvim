---@class FrecencyState
---@field picker TelescopePicker?
local State = {}

---@return FrecencyState
State.new = function()
  return setmetatable({}, { __index = State, __meta = "kv" })
end

---@param picker TelescopePicker?
---@return nil
function State:set(picker)
  self.picker = picker
end

---@return TelescopePicker?
function State:get()
  return self.picker
end

return State

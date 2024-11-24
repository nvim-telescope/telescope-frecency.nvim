local Default = require "frecency.sorter.default"

---@class FrecencySorterOpened: FrecencySorterDefault
local Opened = setmetatable({}, { __index = Default })

---@return FrecencySorterOpened
Opened.new = function()
  return setmetatable(Default.new(), { __index = Opened }) --[[@as FrecencySorterOpened]]
end

return Opened

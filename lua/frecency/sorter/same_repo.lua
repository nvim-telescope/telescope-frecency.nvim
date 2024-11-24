local Opened = require "frecency.sorter.opened"

---@class FrecencySorterSameRepo: FrecencySorterOpened
local SameRepo = setmetatable({}, { __index = Opened })

---@return FrecencySorterSameRepo
SameRepo.new = function()
  return setmetatable(Opened.new(), { __index = SameRepo }) --[[@as FrecencySorterSameRepo]]
end

return SameRepo

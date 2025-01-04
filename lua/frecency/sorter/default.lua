---@class FrecencySorterDefault: FrecencySorter
local Default = {}

---@return FrecencySorterDefault
Default.new = function()
  return setmetatable({}, { __index = Default })
end

---@param entries FrecencyDatabaseEntry[]
---@return FrecencyDatabaseEntry[]
function Default.sort(_, entries)
  table.sort(entries, function(a, b)
    return a.score > b.score or (a.score == b.score and a.path > b.path)
  end)
  return entries
end

return Default

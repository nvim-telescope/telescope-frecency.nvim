---@class FrecencySorterDefault: FrecencySorter
local Default = {}

---@return FrecencySorterDefault
Default.new = function()
  return setmetatable({}, { __index = Default })
end

---@param files FrecencyDatabaseEntry[]
---@return FrecencyDatabaseEntry[]
function Default.sort(_, files)
  table.sort(files, function(a, b)
    return a.score > b.score or (a.score == b.score and a.path > b.path)
  end)
  return files
end

return Default

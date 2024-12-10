local Default = require "frecency.sorter.default"
local Opened = require "frecency.sorter.opened"

---@class FrecencySorterSameRepo: FrecencySorterOpened
---@field private repos string[]
local SameRepo = setmetatable({}, { __index = Opened })

---@return FrecencySorterSameRepo
SameRepo.new = function()
  local self = setmetatable(Opened.new(), { __index = SameRepo }) --[[@as FrecencySorterSameRepo]]
  self.repos = vim
    .iter(self.buffers)
    :map(function(buffer)
      return vim.fs.root(buffer, ".git")
    end)
    :totable()
  return self
end

function SameRepo:sort(files)
  local sorted = Default.sort(self, files)
  if #self.repos == 0 then
    return sorted
  end
  ---@type FrecencyDatabaseEntry[], FrecencyDatabaseEntry[]
  local result, others = {}, {}
  for _, entry in ipairs(sorted) do
    local matched = vim.iter(self.repos):find(function(repo)
      return not not entry.path:find(repo, 1, true)
    end)
    table.insert(matched and result or others, entry)
  end
  for _, entry in ipairs(others) do
    table.insert(result, entry)
  end
  return result
end

return SameRepo

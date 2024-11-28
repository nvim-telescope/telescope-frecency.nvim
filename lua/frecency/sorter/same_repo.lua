local Default = require "frecency.sorter.default"
local Opened = require "frecency.sorter.opened"

---@class FrecencySorterSameRepo: FrecencySorterOpened
---@field private repos string[]
local SameRepo = setmetatable({}, { __index = Opened })

---@return FrecencySorterSameRepo
SameRepo.new = function()
  local self = setmetatable(Opened.new(), { __index = SameRepo }) --[[@as FrecencySorterSameRepo]]
  self.repos = {}
  for _, h in ipairs(self.buffers) do
    local buffer_name = vim.api.nvim_buf_get_name(h)
    local is_loaded = vim.api.nvim_buf_is_loaded(h)
    local repo = vim.fs.root(buffer_name, ".git")
    if repo and is_loaded then
      table.insert(self.repos, repo)
    end
  end
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
    local matched
    for _, repo in ipairs(self.repos) do
      matched = not not entry.path:find(repo, 1, true)
      if matched then
        break
      end
    end
    table.insert(matched and result or others, entry)
  end
  for _, entry in ipairs(others) do
    table.insert(result, entry)
  end
  return result
end

return SameRepo

local Default = require "frecency.sorter.default"

---@class FrecencySorterOpened: FrecencySorterDefault
---@field protected buffers string[]
---@field protected buffers_map table<string, boolean>
local Opened = setmetatable({}, { __index = Default })

---@return FrecencySorterOpened
Opened.new = function()
  local self = setmetatable(Default.new(), { __index = Opened }) --[[@as FrecencySorterOpened]]
  return self:init()
end

---@private
---@return FrecencySorterOpened
function Opened:init()
  local it = vim.iter(vim.api.nvim_list_bufs()):filter(vim.api.nvim_buf_is_loaded):map(vim.api.nvim_buf_get_name)
  self.buffers = it:totable()
  self.buffers_map = it:fold({}, function(a, b)
    a[b] = true
    return a
  end)
  return self
end

function Opened:sort(files)
  local sorted = Default.sort(self, files)
  ---@type FrecencyDatabaseEntry[], FrecencyDatabaseEntry[]
  local result, others = {}, {}
  for _, entry in ipairs(sorted) do
    table.insert(self.buffers_map[entry.path] and result or others, entry)
  end
  for _, entry in ipairs(others) do
    table.insert(result, entry)
  end
  return result
end

return Opened

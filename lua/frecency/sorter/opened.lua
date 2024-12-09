local Default = require "frecency.sorter.default"

---@class FrecencySorterOpened: FrecencySorterDefault
---@field protected buffers string[]
---@field protected buffers_map table<string, boolean>
local Opened = setmetatable({}, { __index = Default })

---@return FrecencySorterOpened
Opened.new = function()
  local self = setmetatable(Default.new(), { __index = Opened }) --[[@as FrecencySorterOpened]]
  local bufnrs = vim.api.nvim_list_bufs()
  self.buffers = {}
  self.buffers_map = {}
  for _, bufnr in ipairs(bufnrs) do
    local is_loaded = vim.api.nvim_buf_is_loaded(bufnr)
    if is_loaded then
      local buffer = vim.api.nvim_buf_get_name(bufnr)
      table.insert(self.buffers, buffer)
      self.buffers_map[buffer] = true
    end
  end
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

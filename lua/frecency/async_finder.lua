local async = require "plenary.async"

---@class FrecencyAsyncFinder
---@field closed boolean
---@field entries FrecencyEntry[]
---@field rx FrecencyRx
---@overload fun(_: string, process_result: (fun(entry: FrecencyEntry): nil), process_complete: fun(): nil): nil
local AsyncFinder = {}

---@class FrecencyRx
---@field recv fun(): FrecencyEntry?

---@class FrecencyTx
---@field send fun(entry: FrecencyEntry?): nil

---@param fs FrecencyFS
---@param path string
---@param entry_maker fun(file: FrecencyFile): FrecencyEntry
---@param initial_results FrecencyFile[]
---@return FrecencyAsyncFinder
AsyncFinder.new = function(fs, path, entry_maker, initial_results)
  local self = setmetatable({ closed = false, entries = {} }, {
    __index = AsyncFinder,
    ---@param self FrecencyAsyncFinder
    __call = function(self, ...)
      return self:find(...)
    end,
  })
  local seen = {}
  for i, file in ipairs(initial_results) do
    local entry = entry_maker(file)
    seen[entry.filename] = true
    entry.index = i
    table.insert(self.entries, entry)
  end
  local it = vim.F.nil_wrap(fs:scan_dir(path))
  local index = #initial_results
  local count = 0
  ---@type FrecencyTx, FrecencyRx
  local tx, rx = async.control.channel.mpsc()
  self.rx = rx
  async.run(function()
    for name in it do
      if self.closed then
        break
      end
      local fullpath = vim.fs.joinpath(path, name)
      if not seen[fullpath] then
        seen[fullpath] = true
        index = index + 1
        count = count + 1
        local entry = entry_maker { id = 0, count = 0, path = vim.fs.joinpath(path, name), score = 0 }
        if entry then
          entry.index = index
          table.insert(self.entries, entry)
          tx.send(entry)
          if count % 1000 == 0 then
            -- NOTE: This is needed not to lock text input.
            async.util.sleep(0)
          end
        end
      end
    end
    self:close()
    tx.send(nil)
  end)
  return self
end

---@param _ string
---@param process_result fun(entry: FrecencyEntry): nil
---@param process_complete fun(): nil
---@return nil
function AsyncFinder:find(_, process_result, process_complete)
  for _, entry in ipairs(self.entries) do
    if process_result(entry) then
      return
    end
  end
  local count = 0
  local last_index = self.entries[#self.entries].index
  while true do
    if self.closed then
      break
    end
    local entry = self.rx.recv()
    if entry then
      if entry.index > last_index then
        if process_result(entry) then
          return
        end
        count = count + 1
      end
    else
      break
    end
  end
  process_complete()
end

function AsyncFinder:close()
  self.closed = true
end

return AsyncFinder

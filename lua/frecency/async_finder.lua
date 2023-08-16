local async = require "plenary.async" --[[@as PlenaryAsync]]

---@class FrecencyAsyncFinder
---@field closed boolean
---@field entries FrecencyEntry[]
---@field reflowed boolean
---@field rx PlenaryAsyncControlChannelRx
---@field state FrecencyState
---@overload fun(_: string, process_result: (fun(entry: FrecencyEntry): nil), process_complete: fun(): nil): nil
local AsyncFinder = {}

---@param fs FrecencyFS
---@param state FrecencyState
---@param path string
---@param entry_maker fun(file: FrecencyFile): FrecencyEntry
---@param initial_results FrecencyFile[]
---@return FrecencyAsyncFinder
AsyncFinder.new = function(state, fs, path, entry_maker, initial_results)
  local self = setmetatable({ closed = false, entries = {}, reflowed = false, state = state }, {
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
  local tx, rx = async.control.channel.mpsc()
  self.rx = rx
  async.run(function()
    local index = #initial_results
    local count = 0
    for name in fs:scan_dir(path) do
      if self.closed then
        break
      end
      local fullpath = fs.joinpath(path, name)
      if not seen[fullpath] then
        seen[fullpath] = true
        index = index + 1
        count = count + 1
        local entry = entry_maker { id = 0, count = 0, path = fs.joinpath(path, name), score = 0 }
        if entry then
          entry.index = index
          table.insert(self.entries, entry)
          tx.send(entry)
          if count % 1000 == 0 then
            self:reflow_results()
            -- NOTE: This is needed not to lock text input.
            async.util.sleep(50)
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
  local last_index = self.entries[#self.entries].index
  while true do
    if self.closed then
      break
    end
    local entry = self.rx.recv()
    if not entry then
      break
    elseif entry.index > last_index and process_result(entry) then
      return
    end
  end
  process_complete()
end

function AsyncFinder:close()
  self.closed = true
end

---@return nil
function AsyncFinder:reflow_results()
  local picker = self.state:get()
  if not picker then
    return
  end
  local bufnr = picker.results_bufnr
  local win = picker.results_win
  if not bufnr or not win then
    return
  end
  picker:clear_extra_rows(bufnr)
  if picker.sorting_strategy == "descending" then
    local manager = picker.manager
    if not manager then
      return
    end
    local worst_line = picker:get_row(manager:num_results())
    ---@type WinInfo
    local wininfo = vim.fn.getwininfo(win)[1]
    local bottom = vim.api.nvim_buf_line_count(bufnr)
    if not self.reflowed or worst_line > wininfo.botline then
      self.reflowed = true
      vim.api.nvim_win_set_cursor(win, { bottom, 0 })
    end
    if not picker:get_selection() then
      local prompt = picker:_get_prompt()
      picker:_do_selection(prompt)
    end
  end
end

return AsyncFinder

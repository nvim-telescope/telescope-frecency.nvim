local async = require "plenary.async" --[[@as PlenaryAsync]]
local log = require "plenary.log"

---@class FrecencyFinder
---@field config FrecencyFinderConfig
---@field closed boolean
---@field entries FrecencyEntry[]
---@field entry_maker FrecencyEntryMakerInstance
---@field fs FrecencyFS
---@field need_scandir boolean
---@field path string?
---@field private database FrecencyDatabase
---@field private recency FrecencyRecency
---@field private rx PlenaryAsyncControlChannelRx
---@field private state FrecencyState
---@field private tx PlenaryAsyncControlChannelTx
local Finder = {}

---@class FrecencyFinderConfig
---@field chunk_size integer default: 1000
---@field sleep_interval integer default: 50

---@param database FrecencyDatabase
---@param entry_maker FrecencyEntryMakerInstance
---@param fs FrecencyFS
---@param need_scandir boolean
---@param path string?
---@param recency FrecencyRecency
---@param state FrecencyState
---@param config FrecencyFinderConfig?
---@return FrecencyFinder
Finder.new = function(database, entry_maker, fs, need_scandir, path, recency, state, config)
  local tx, rx = async.control.channel.mpsc()
  return setmetatable({
    config = vim.tbl_extend("force", { chunk_size = 1000, sleep_interval = 50 }, config or {}),
    closed = false,
    database = database,
    entries = {},
    entry_maker = entry_maker,
    fs = fs,
    need_scandir = need_scandir,
    path = path,
    recency = recency,
    rx = rx,
    state = state,
    tx = tx,
  }, {
    __index = Finder,
    ---@param self FrecencyFinder
    __call = function(self, ...)
      return self:find(...)
    end,
  })
end

---@param datetime string?
---@return nil
function Finder:start(datetime)
  async.void(function()
    -- NOTE: return to the main loop to show the main window
    async.util.sleep(0)
    local seen = {}
    for i, file in ipairs(self:get_results(self.path, datetime)) do
      local entry = self.entry_maker(file)
      seen[entry.filename] = true
      entry.index = i
      table.insert(self.entries, entry)
      self.tx.send(entry)
    end
    if self.need_scandir and self.path then
      -- NOTE: return to the main loop to show results from DB
      async.util.sleep(self.config.sleep_interval)
      self:scan_dir(seen)
    end
    self:close()
    self.tx.send(nil)
  end)()
end

---@param seen table<string, boolean>
---@return nil
function Finder:scan_dir(seen)
  local count = 0
  local index = #self.entries
  for name in self.fs:scan_dir(self.path) do
    if self.closed then
      break
    end
    local fullpath = self.fs.joinpath(self.path, name)
    if not seen[fullpath] then
      seen[fullpath] = true
      count = count + 1
      local entry = self.entry_maker { id = 0, count = 0, path = fullpath, score = 0 }
      if entry then
        index = index + 1
        entry.index = index
        table.insert(self.entries, entry)
        self.tx.send(entry)
        if count % self.config.chunk_size == 0 then
          self:reflow_results()
          async.util.sleep(self.config.sleep_interval)
        end
      end
    end
  end
end

---@param _ string
---@param process_result fun(entry: FrecencyEntry): nil
---@param process_complete fun(): nil
---@return nil
function Finder:find(_, process_result, process_complete)
  local index = 0
  for _, entry in ipairs(self.entries) do
    index = index + 1
    if process_result(entry) then
      return
    end
  end
  local count = 0
  while not self.closed do
    count = count + 1
    local entry = self.rx.recv()
    if not entry then
      break
    elseif entry.index > index and process_result(entry) then
      return
    end
  end
  process_complete()
end

---@param workspace string?
---@param datetime string?
---@return FrecencyFile[]
function Finder:get_results(workspace, datetime)
  log.debug { workspace = workspace or "NONE" }
  local start_fetch = os.clock()
  local files = self.database:get_entries(workspace, datetime)
  log.debug(("it takes %f seconds in fetching entries"):format(os.clock() - start_fetch))
  local start_results = os.clock()
  local elapsed_recency = 0
  for _, file in ipairs(files) do
    local start_recency = os.clock()
    file.score = file.ages and self.recency:calculate(file.count, file.ages) or 0
    file.ages = nil
    elapsed_recency = elapsed_recency + (os.clock() - start_recency)
  end
  log.debug(("it takes %f seconds in calculating recency"):format(elapsed_recency))
  log.debug(("it takes %f seconds in making results"):format(os.clock() - start_results))

  local start_sort = os.clock()
  table.sort(files, function(a, b)
    return a.score > b.score or (a.score == b.score and a.path > b.path)
  end)
  log.debug(("it takes %f seconds in sorting"):format(os.clock() - start_sort))
  return files
end

function Finder:close()
  self.closed = true
end

function Finder:reflow_results()
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
  end
end

return Finder

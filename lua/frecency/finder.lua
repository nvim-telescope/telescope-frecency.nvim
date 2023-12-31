local Job = require "plenary.job"
local async = require "plenary.async" --[[@as PlenaryAsync]]
local log = require "plenary.log"

---@class FrecencyFinder
---@field config FrecencyFinderConfig
---@field closed boolean
---@field entries FrecencyEntry[]
---@field scanned_entries FrecencyEntry[]
---@field entry_maker FrecencyEntryMakerInstance
---@field fs FrecencyFS
---@field path string?
---@field private database FrecencyDatabase
---@field private rx PlenaryAsyncControlChannelRx
---@field private tx PlenaryAsyncControlChannelTx
---@field private scan_rx PlenaryAsyncControlChannelRx
---@field private scan_tx PlenaryAsyncControlChannelTx
---@field private need_scan_db boolean
---@field private need_scan_dir boolean
---@field private seen table<string, boolean>
---@field private process VimSystemObj?
---@field private recency FrecencyRecency
---@field private state FrecencyState
local Finder = {}

---@class FrecencyFinderConfig
---@field chunk_size integer? default: 1000
---@field sleep_interval integer? default: 50
---@field workspace_scan_cmd "LUA"|string[]|nil default: nil

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
  local scan_tx, scan_rx = async.control.channel.mpsc()
  return setmetatable({
    config = vim.tbl_extend("force", { chunk_size = 1000, sleep_interval = 50 }, config or {}),
    closed = false,
    database = database,
    entry_maker = entry_maker,
    fs = fs,
    path = path,
    recency = recency,
    state = state,

    seen = {},
    entries = {},
    scanned_entries = {},
    need_scan_db = true,
    need_scan_dir = need_scandir and path,
    rx = rx,
    tx = tx,
    scan_rx = scan_rx,
    scan_tx = scan_tx,
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
  local cmd = self.config.workspace_scan_cmd
  local ok
  if cmd ~= "LUA" and self.need_scan_dir then
    ---@type string[][]
    local cmds = cmd and { cmd } or { { "rg", "-.g", "!.git", "--files" }, { "fdfind", "-Htf" }, { "fd", "-Htf" } }
    for _, c in ipairs(cmds) do
      ok = self:scan_dir_cmd(c)
      if ok then
        log.debug("scan_dir_cmd: " .. vim.inspect(c))
        break
      end
    end
  end
  async.void(function()
    -- NOTE: return to the main loop to show the main window
    async.util.scheduler()
    for _, file in ipairs(self:get_results(self.path, datetime)) do
      local entry = self.entry_maker(file)
      self.tx.send(entry)
    end
    self.tx.send(nil)
    if self.need_scan_dir and not ok then
      log.debug "scan_dir_lua"
      async.util.scheduler()
      self:scan_dir_lua()
    end
  end)()
end

---@param cmd string[]
---@return boolean
function Finder:scan_dir_cmd(cmd)
  local function stdout(err, chunk)
    if not self.closed and not err and chunk then
      for name in chunk:gmatch "[^\n]+" do
        local cleaned = name:gsub("^%./", "")
        local fullpath = self.fs.joinpath(self.path, cleaned)
        local entry = self.entry_maker { id = 0, count = 0, path = fullpath, score = 0 }
        self.scan_tx.send(entry)
      end
    end
  end

  local function on_exit()
    self.process = nil
    self:close()
    self.scan_tx.send(nil)
  end

  local ok
  if vim.system then
    ---@diagnostic disable-next-line: assign-type-mismatch
    ok, self.process = pcall(vim.system, cmd, {
      cwd = self.path,
      text = true,
      stdout = stdout,
    }, on_exit)
  else
    -- for Neovim v0.9.x
    ok, self.process = pcall(function()
      local args = {}
      for i, arg in ipairs(cmd) do
        if i > 1 then
          table.insert(args, arg)
        end
      end
      log.debug { cmd = cmd[1], args = args }
      local job = Job:new {
        cwd = self.path,
        command = cmd[1],
        args = args,
        on_stdout = stdout,
        on_exit = on_exit,
      }
      job:start()
      return job.handle
    end)
  end
  if not ok then
    self.process = nil
  end
  return ok
end

---@async
---@return nil
function Finder:scan_dir_lua()
  local count = 0
  for name in self.fs:scan_dir(self.path) do
    if self.closed then
      break
    end
    local fullpath = self.fs.joinpath(self.path, name)
    local entry = self.entry_maker { id = 0, count = 0, path = fullpath, score = 0 }
    self.scan_tx.send(entry)
    count = count + 1
    if count % self.config.chunk_size == 0 then
      async.util.sleep(self.config.sleep_interval)
    end
  end
  self.scan_tx.send(nil)
end

---@async
---@param _ string
---@param process_result fun(entry: FrecencyEntry): nil
---@param process_complete fun(): nil
---@return nil
function Finder:find(_, process_result, process_complete)
  if self:process_table(process_result, self.entries) then
    return
  end
  if self.need_scan_db then
    if self:process_channel(process_result, self.entries, self.rx) then
      return
    end
    self.need_scan_db = false
  end
  -- HACK: This is needed for heavy workspaces to show up entries immediately.
  async.util.scheduler()
  if self:process_table(process_result, self.scanned_entries) then
    return
  end
  if self.need_scan_dir then
    if self:process_channel(process_result, self.scanned_entries, self.scan_rx, #self.entries) then
      return
    end
    self.need_scan_dir = false
  end
  process_complete()
end

---@param process_result fun(entry: FrecencyEntry): nil
---@param entries FrecencyEntry[]
---@return boolean?
function Finder:process_table(process_result, entries)
  for _, entry in ipairs(entries) do
    if process_result(entry) then
      return true
    end
  end
end

---@async
---@param process_result fun(entry: FrecencyEntry): nil
---@param entries FrecencyEntry[]
---@param rx PlenaryAsyncControlChannelRx
---@param start_index integer?
---@return boolean?
function Finder:process_channel(process_result, entries, rx, start_index)
  -- HACK: This is needed for small workspaces that it shows up entries fast.
  async.util.sleep(self.config.sleep_interval)
  local index = #entries > 0 and entries[#entries].index or start_index or 0
  local count = 0
  while true do
    local entry = rx.recv()
    if not entry then
      break
    elseif not self.seen[entry.filename] then
      self.seen[entry.filename] = true
      index = index + 1
      entry.index = index
      table.insert(entries, entry)
      if process_result(entry) then
        return true
      end
    end
    count = count + 1
    if count % self.config.chunk_size == 0 then
      self:reflow_results()
    end
  end
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
  if self.process then
    self.process:kill(9)
  end
end

---@async
---@return nil
function Finder:reflow_results()
  local picker = self.state:get()
  if not picker then
    return
  end
  async.util.scheduler()
  local bufnr = picker.results_bufnr
  local win = picker.results_win
  if not bufnr or not win or not vim.api.nvim_buf_is_valid(bufnr) or not vim.api.nvim_win_is_valid(win) then
    return
  end
  picker:clear_extra_rows(bufnr)
  if picker.sorting_strategy == "descending" then
    local manager = picker.manager
    if not manager then
      return
    end
    local worst_line = picker:get_row(manager:num_results())
    local wininfo = vim.fn.getwininfo(win)[1]
    local bottom = vim.api.nvim_buf_line_count(bufnr)
    if not self.reflowed or worst_line > wininfo.botline then
      self.reflowed = true
      vim.api.nvim_win_set_cursor(win, { bottom, 0 })
    end
  end
end

return Finder

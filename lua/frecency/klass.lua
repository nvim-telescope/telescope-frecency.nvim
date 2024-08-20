local Database = require "frecency.database"
local EntryMaker = require "frecency.entry_maker"
local Picker = require "frecency.picker"
local Recency = require "frecency.recency"
local config = require "frecency.config"
local fs = require "frecency.fs"
local log = require "frecency.log"
local async = require "plenary.async" --[[@as FrecencyPlenaryAsync]]

---@class Frecency
---@field private buf_registered table<integer, boolean> flag to indicate the buffer is registered to the database.
---@field private database FrecencyDatabase
---@field private entry_maker FrecencyEntryMaker
---@field private picker FrecencyPicker
---@field private recency FrecencyRecency
local Frecency = {}

---@return Frecency
Frecency.new = function()
  local self = setmetatable({ buf_registered = {} }, { __index = Frecency }) --[[@as Frecency]]
  self.database = Database.new()
  self.entry_maker = EntryMaker.new()
  self.recency = Recency.new()
  return self
end

---This is called when `:Telescope frecency` is called at the first time.
---@return nil
function Frecency:setup()
  local done = false
  ---@async
  local function init()
    self.database:start()
    self:assert_db_entries()
    if config.auto_validate then
      self:validate_database()
    end
    done = true
  end

  local is_async = not not coroutine.running()
  if is_async then
    init()
  else
    async.void(init)()
    local ok, status = vim.wait(10000, function()
      return done
    end)
    if not ok then
      error("failed to setup:" .. (status == -1 and "timed out" or "interrupted"))
    end
  end
end

---This can be calledBy `require("telescope").extensions.frecency.frecency`.
---@param opts? FrecencyPickerOptions
---@return nil
function Frecency:start(opts)
  local start = os.clock()
  log.debug "Frecency:start"
  opts = opts or {}
  if opts.cwd then
    opts.cwd = vim.fn.expand(opts.cwd)
  end
  local ignore_filenames
  if opts.hide_current_buffer or config.hide_current_buffer then
    ignore_filenames = { vim.api.nvim_buf_get_name(0) }
  end
  self.picker = Picker.new(self.database, self.entry_maker, self.recency, {
    editing_bufnr = vim.api.nvim_get_current_buf(),
    ignore_filenames = ignore_filenames,
    initial_workspace_tag = opts.workspace,
  })
  self.picker:start(vim.tbl_extend("force", config.get(), opts))
  log.debug(("Frecency:start picker:start takes %f seconds"):format(os.clock() - start))
end

---This can be calledBy `require("telescope").extensions.frecency.complete`.
---@param findstart 1|0
---@param base string
---@return integer|''|string[]
function Frecency:complete(findstart, base)
  return self.picker:complete(findstart, base)
end

---@async
---@param force? boolean
---@return nil
function Frecency:validate_database(force)
  local unlinked = self.database:unlinked_entries()
  if #unlinked == 0 or (not force and #unlinked < config.db_validate_threshold) then
    return
  end
  local function remove_entries()
    self.database:remove_files(unlinked)
    self:notify("removed %d missing entries.", #unlinked)
  end
  if not config.db_safe_mode then
    remove_entries()
    return
  end
  -- HACK: This is needed because the default implementaion of vim.ui.select()
  -- uses vim.fn.* function and it makes E5560 error.
  async.util.scheduler()
  vim.ui.select({ "y", "n" }, {
    prompt = self:message("remove %d entries from database?", #unlinked),
    ---@param item "y"|"n"
    ---@return string
    format_item = function(item)
      return item == "y" and "Yes. Remove them." or "No. Do nothing."
    end,
  }, function(item)
    if item == "y" then
      remove_entries()
    else
      self:notify "validation aborted"
    end
  end)
end

---@private
---@async
---@return nil
function Frecency:assert_db_entries()
  if not self.database:has_entry() then
    self.database:insert_files(vim.v.oldfiles)
    self:notify("Imported %d entries from oldfiles.", #vim.v.oldfiles)
  end
end

---@param bufnr integer
---@param epoch? integer
function Frecency:register(bufnr, epoch)
  if (config.ignore_register and config.ignore_register(bufnr)) or self.buf_registered[bufnr] then
    return
  end
  local path = vim.api.nvim_buf_get_name(bufnr)
  async.void(function()
    if not fs.is_valid_path(path) then
      return
    end
    local err, realpath = async.uv.fs_realpath(path)
    if err or not realpath then
      return
    end
    self.database:update(realpath, epoch)
    self.buf_registered[bufnr] = true
    log.debug("registered:", bufnr, path)
  end)()
end

---@async
---@param path string
---@return nil
function Frecency:delete(path)
  if self.database:remove_entry(path) then
    self:notify("successfully deleted: %s", path)
  else
    self:warn("failed to delete: %s", path)
  end
end

---@alias FrecencyQueryOrder "count"|"path"|"score"|"timestamps"
---@alias FrecencyQueryDirection "asc"|"desc"

---@class FrecencyQueryOpts
---@field direction? "asc"|"desc" default: "desc"
---@field limit? integer default: 100
---@field order? FrecencyQueryOrder default: "score"
---@field record? boolean default: false
---@field workspace? string default: nil

---@class FrecencyQueryEntry
---@field count integer
---@field path string
---@field score number
---@field timestamps integer[]

---@param opts? FrecencyQueryOpts
---@param epoch? integer
---@return FrecencyQueryEntry[]|string[]
function Frecency:query(opts, epoch)
  opts = vim.tbl_extend("force", {
    direction = "desc",
    limit = 100,
    order = "score",
    record = false,
  }, opts or {})
  ---@param entry FrecencyDatabaseEntry
  local entries = vim.tbl_map(function(entry)
    return {
      count = entry.count,
      path = entry.path,
      score = entry.ages and self.recency:calculate(entry.count, entry.ages) or 0,
      timestamps = entry.timestamps,
    }
  end, self.database:get_entries(opts.workspace, epoch))
  table.sort(entries, self:query_sorter(opts.order, opts.direction))
  local results = opts.record and entries or vim.tbl_map(function(entry)
    return entry.path
  end, entries)
  if #results > opts.limit then
    return vim.list_slice(results, 1, opts.limit)
  end
  return results
end

---@private
---@param order FrecencyQueryOrder
---@param direction FrecencyQueryDirection
---@return fun(a: FrecencyQueryEntry, b: FrecencyQueryEntry): boolean
function Frecency:query_sorter(order, direction)
  local is_asc = direction == "asc"
  if order == "count" then
    if is_asc then
      return function(a, b)
        return a.count < b.count or (a.count == b.count and a.path < b.path)
      end
    end
    return function(a, b)
      return a.count > b.count or (a.count == b.count and a.path < b.path)
    end
  elseif order == "path" then
    if is_asc then
      return function(a, b)
        return a.path < b.path
      end
    end
    return function(a, b)
      return a.path > b.path
    end
  elseif order == "score" then
    if is_asc then
      return function(a, b)
        return a.score < b.score or (a.score == b.score and a.path < b.path)
      end
    end
    return function(a, b)
      return a.score > b.score or (a.score == b.score and a.path < b.path)
    end
  elseif is_asc then
    return function(a, b)
      local a_timestamp = a.timestamps[1] or 0
      local b_timestamp = b.timestamps[1] or 0
      return a_timestamp < b_timestamp or (a_timestamp == b_timestamp and a.path < b.path)
    end
  end
  return function(a, b)
    local a_timestamp = a.timestamps[1] or 0
    local b_timestamp = b.timestamps[1] or 0
    return a_timestamp > b_timestamp or (a_timestamp == b_timestamp and a.path < b.path)
  end
end

---@private
---@param fmt string
---@param ...? any
---@return string
function Frecency:message(fmt, ...)
  return ("[Telescope-Frecency] " .. fmt):format(unpack { ... })
end

---@private
---@param fmt string
---@param ...? any
---@return nil
function Frecency:notify(fmt, ...)
  vim.notify(self:message(fmt, ...))
end

---@private
---@param fmt string
---@param ...? any
---@return nil
function Frecency:warn(fmt, ...)
  vim.notify(self:message(fmt, ...), vim.log.levels.WARN)
end

---@private
---@param fmt string
---@param ...? any
---@return nil
function Frecency:error(fmt, ...)
  vim.notify(self:message(fmt, ...), vim.log.levels.ERROR)
end

return Frecency

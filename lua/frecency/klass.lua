local Database = require "frecency.database"
local Picker = require "frecency.picker"
local config = require "frecency.config"
local fs = require "frecency.fs"
local log = require "frecency.log"
local timer = require "frecency.timer"
local wait = require "frecency.wait"
local lazy_require = require "frecency.lazy_require"
local async = lazy_require "plenary.async" --[[@as FrecencyPlenaryAsync]]

---@enum FrecencyStatus
local STATUS = {
  NEW = 0,
  SETUP_CALLED = 1,
  DB_STARTED = 2,
  CLEANUP_FINISHED = 3,
}

---@class Frecency
---@field private buf_registered table<integer, boolean> flag to indicate the buffer is registered to the database.
---@field private database FrecencyDatabase
---@field private picker FrecencyPicker
---@field private status FrecencyStatus
local Frecency = {}

---@param database? FrecencyDatabase
---@return Frecency
Frecency.new = function(database)
  local self = setmetatable({ buf_registered = {}, status = STATUS.NEW }, { __index = Frecency }) --[[@as Frecency]]
  self.database = database or Database.create(config.db_version)
  return self
end

---This is called when `:Telescope frecency` is called at the first time.
---@param is_async boolean
---@param need_cleanup boolean
---@return nil
function Frecency:setup(is_async, need_cleanup)
  if self.status == STATUS.CLEANUP_FINISHED then
    return
  elseif self.status == STATUS.NEW then
    self.status = STATUS.SETUP_CALLED
  end
  timer.track "frecency.setup() start"

  ---@async
  local function init()
    if self.status == STATUS.SETUP_CALLED then
      self.database:start()
      self.status = STATUS.DB_STARTED
      timer.track "DB_STARTED"
    end
    if self.status == STATUS.DB_STARTED and need_cleanup then
      self:assert_db_entries()
      if config.auto_validate then
        self:validate_database()
      end
      self.status = STATUS.CLEANUP_FINISHED
      timer.track "CLEANUP_FINISHED"
    end
    timer.track "frecency.setup() finish"
  end

  if is_async then
    init()
    return
  end

  local ok, status = wait(init)
  if ok then
    return
  end
  -- NOTE: This means init() has failed. Try again.
  self:error(status == -1 and "init() never returns during the time" or "init() is interrupted during the time")
end

---This can be calledBy `require("telescope").extensions.frecency.frecency`.
---@param opts? FrecencyPickerOptions
---@return nil
function Frecency:start(opts)
  timer.track "start() start"
  log.debug "Frecency:start"
  opts = opts or {}
  if opts.cwd then
    opts.cwd = vim.fn.expand(opts.cwd)
  end
  local ignore_filenames
  if opts.hide_current_buffer or config.hide_current_buffer then
    ignore_filenames = { vim.api.nvim_buf_get_name(0) }
  end
  self.picker = Picker.new(self.database, {
    editing_bufnr = vim.api.nvim_get_current_buf(),
    ignore_filenames = ignore_filenames,
    initial_workspace_tag = opts.workspace,
  })
  self.picker:start(vim.tbl_extend("force", config.get(), opts))
  timer.track "start() finish"
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
  self:_validate_database(force)
  if self.status == STATUS.DB_STARTED then
    self.status = STATUS.CLEANUP_FINISHED
  end
  timer.track "CLEANUP_FINISHED"
end

---@private
---@async
---@param force? boolean
---@return nil
function Frecency:_validate_database(force)
  timer.track "validate_database() start"
  local unlinked = self.database:unlinked_entries()
  timer.track "validate_database() calculate unlinked"
  if #unlinked == 0 or (not force and #unlinked < config.db_validate_threshold) then
    timer.track "validate_database() finish: no unlinked"
    return
  end
  local function remove_entries()
    self.database:remove_files(unlinked)
    self:notify("removed %d missing entries.", #unlinked)
  end
  if not config.db_safe_mode then
    remove_entries()
    timer.track "validate_database() finish: removed"
    return
  end
  -- HACK: This is needed because the default implementaion of vim.ui.select()
  -- uses vim.fn.* function and it makes E5560 error.
  async.util.scheduler()
  vim.ui.select({ "y", "n" }, {
    prompt = "\n" .. self:message("remove %d entries from database?", #unlinked),
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

---@async
---@param bufnr integer
---@param path string
---@param epoch? integer
function Frecency:register(bufnr, path, epoch)
  if self.buf_registered[bufnr] or not fs.is_valid_path(path) then
    return
  end
  local err, realpath = async.uv.fs_realpath(path)
  if err or not realpath then
    return
  end
  self.database:update(realpath, epoch)
  self.buf_registered[bufnr] = true
  log.debug("registered:", bufnr, path)
end

---@param bufnr integer
---@return nil
function Frecency:unregister(bufnr)
  self.buf_registered[bufnr] = nil
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
---@field json? boolean default: false
---@field limit? integer default: 100
---@field order? FrecencyQueryOrder default: "score"
---@field record? boolean default: false
---@field workspace? string|string[] default: nil

---@class FrecencyQueryEntry
---@field count integer
---@field path string
---@field score number
---@field timestamps integer[]

---@param opts? FrecencyQueryOpts
---@param epoch? integer
---@return string|FrecencyQueryEntry[]|string[]
function Frecency:query(opts, epoch)
  opts = vim.tbl_extend("force", {
    direction = "desc",
    json = false,
    limit = 100,
    order = "score",
    record = false,
  }, opts or {})
  local workspaces = type(opts.workspace) == "table" and opts.workspace
    or type(opts.workspace) == "string" and { opts.workspace }
    or nil
  local objects = vim
    .iter(self.database:get_entries(workspaces, epoch))
    ---@param entry FrecencyDatabaseEntry
    :map(function(entry)
      return entry:obj()
    end)
    :totable()
  table.sort(objects, self.database.query_sorter(opts.order, opts.direction))
  local results = opts.record and objects
    or vim
      .iter(objects)
      :map(function(obj)
        return obj.path
      end)
      :totable()
  if #results > opts.limit then
    results = vim.list_slice(results, 1, opts.limit)
  end
  return opts.json and vim.json.encode(results) or results
end

---@private
---@param fmt string
---@param ...? any
---@return string
function Frecency.message(_, fmt, ...)
  return ("[Telescope-Frecency] " .. fmt):format(unpack { ... })
end

---@private
---@param fmt string
---@param ...? any
---@return nil
function Frecency:notify(fmt, ...)
  self:_notify(self:message(fmt, ...))
end

---@private
---@param fmt string
---@param ...? any
---@return nil
function Frecency:warn(fmt, ...)
  self:_notify(self:message(fmt, ...), vim.log.levels.WARN)
end

---@private
---@param fmt string
---@param ...? any
---@return nil
function Frecency:error(fmt, ...)
  self:_notify(self:message(fmt, ...), vim.log.levels.ERROR)
end

---@param msg string
---@param level? integer
---@param opts? table
function Frecency:_notify(msg, level, opts) -- luacheck: no self
  local ok, err = pcall(vim.notify, msg, level, opts)
  if
    not ok and (err --[[@as string]]):match "E5560"
  then
    print "E5560 detected. doing fallback..."
    print(msg)
  end
end

return Frecency

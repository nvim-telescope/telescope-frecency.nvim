local Database = require "frecency.database"
local EntryMaker = require "frecency.entry_maker"
local FS = require "frecency.fs"
local Picker = require "frecency.picker"
local Recency = require "frecency.recency"
local WebDevicons = require "frecency.web_devicons"
local config = require "frecency.config"
local log = require "plenary.log"

---@class Frecency
---@field private buf_registered table<integer, boolean> flag to indicate the buffer is registered to the database.
---@field private database FrecencyDatabase
---@field private entry_maker FrecencyEntryMaker
---@field private fs FrecencyFS
---@field private picker FrecencyPicker
---@field private recency FrecencyRecency
local Frecency = {}

---@return Frecency
Frecency.new = function()
  local self = setmetatable({ buf_registered = {} }, { __index = Frecency }) --[[@as Frecency]]
  self.fs = FS.new { ignore_patterns = config.ignore_patterns }
  self.database = Database.new(self.fs, { root = config.db_root })
  local web_devicons = WebDevicons.new(not config.disable_devicons)
  self.entry_maker = EntryMaker.new(self.fs, web_devicons, {
    show_filter_column = config.show_filter_column,
    show_scores = config.show_scores,
  })
  self.recency = Recency.new { max_count = config.max_timestamps }
  return self
end

---This is called when `:Telescope frecency` is called at the first time.
---@return nil
function Frecency:setup()
  self:assert_db_entries()
  if config.auto_validate then
    self:validate_database()
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
  self.picker = Picker.new(self.database, self.entry_maker, self.fs, self.recency, {
    default_workspace_tag = config.default_workspace,
    editing_bufnr = vim.api.nvim_get_current_buf(),
    filter_delimiter = config.filter_delimiter,
    ignore_filenames = ignore_filenames,
    initial_workspace_tag = opts.workspace,
    show_unindexed = config.show_unindexed,
    workspace_scan_cmd = config.workspace_scan_cmd,
    workspaces = config.workspaces,
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

---@private
---@return nil
function Frecency:assert_db_entries()
  if not self.database:has_entry() then
    self.database:insert_files(vim.v.oldfiles)
    self:notify("Imported %d entries from oldfiles.", #vim.v.oldfiles)
  end
end

---@private
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

---@param bufnr integer
---@param datetime? string ISO8601 format string
function Frecency:register(bufnr, datetime)
  local path = vim.api.nvim_buf_get_name(bufnr)
  if self.buf_registered[bufnr] or not self.fs:is_valid_path(path) then
    return
  end
  self.database:update(path, self.recency.config.max_count, datetime)
  self.buf_registered[bufnr] = true
end

---@param path string
---@return nil
function Frecency:delete(path)
  if self.database:remove_entry(path) then
    self:notify("successfully deleted: %s", path)
  else
    self:warn("failed to delete: %s", path)
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

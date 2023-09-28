local Sqlite = require "frecency.database.sqlite"
local Native = require "frecency.database.native"
local EntryMaker = require "frecency.entry_maker"
local FS = require "frecency.fs"
local Migrator = require "frecency.migrator"
local Picker = require "frecency.picker"
local Recency = require "frecency.recency"
local WebDevicons = require "frecency.web_devicons"
local sqlite_module = require "frecency.sqlite"
local log = require "plenary.log"

---@class Frecency
---@field config FrecencyConfig
---@field private buf_registered table<integer, boolean> flag to indicate the buffer is registered to the database.
---@field private database FrecencyDatabase
---@field private entry_maker FrecencyEntryMaker
---@field private fs FrecencyFS
---@field private migrator FrecencyMigrator
---@field private picker FrecencyPicker
---@field private recency FrecencyRecency
local Frecency = {}

---@class FrecencyConfig
---@field auto_validate boolean? default: true
---@field db_root string? default: vim.fn.stdpath "data"
---@field db_safe_mode boolean? default: true
---@field db_validate_threshold? integer default: 10
---@field default_workspace string? default: nil
---@field disable_devicons boolean? default: false
---@field filter_delimiter string? default: ":"
---@field ignore_patterns string[]? default: { "*.git/*", "*/tmp/*", "term://*" }
---@field max_timestamps integer? default: 10
---@field show_filter_column boolean|string[]|nil default: true
---@field show_scores boolean? default: false
---@field show_unindexed boolean? default: true
---@field use_sqlite boolean? default: false
---@field workspaces table<string, string>? default: {}

---@param opts FrecencyConfig?
---@return Frecency
Frecency.new = function(opts)
  ---@type FrecencyConfig
  local config = vim.tbl_extend("force", {
    auto_validate = true,
    db_root = vim.fn.stdpath "data",
    db_safe_mode = true,
    db_validate_threshold = 10,
    default_workspace = nil,
    disable_devicons = false,
    filter_delimiter = ":",
    ignore_patterns = { "*.git/*", "*/tmp/*", "term://*" },
    max_timestamps = 10,
    show_filter_column = true,
    show_scores = false,
    show_unindexed = true,
    use_sqlite = false,
    workspaces = {},
  }, opts or {})
  local self = setmetatable({ buf_registered = {}, config = config }, { __index = Frecency })--[[@as Frecency]]
  self.fs = FS.new { ignore_patterns = config.ignore_patterns }

  local Database
  if not self.config.use_sqlite then
    Database = Native
  elseif not sqlite_module.can_use then
    self:warn "use_sqlite = true, but sqlite module can not be found. It fallbacks to native code."
    Database = Native
  else
    self:warn "SQLite mode is deprecated."
    Database = Sqlite
  end
  self.database = Database.new(self.fs, { root = config.db_root })
  local web_devicons = WebDevicons.new(not config.disable_devicons)
  self.entry_maker = EntryMaker.new(self.fs, web_devicons, {
    show_filter_column = config.show_filter_column,
    show_scores = config.show_scores,
  })
  local max_count = config.max_timestamps > 0 and config.max_timestamps or 10
  self.recency = Recency.new { max_count = max_count }
  self.migrator = Migrator.new(self.fs, self.recency, self.config.db_root)
  return self
end

---@return nil
function Frecency:setup()
  vim.api.nvim_set_hl(0, "TelescopeBufferLoaded", { link = "String", default = true })
  vim.api.nvim_set_hl(0, "TelescopePathSeparator", { link = "Directory", default = true })
  vim.api.nvim_set_hl(0, "TelescopeFrecencyScores", { link = "Number", default = true })
  vim.api.nvim_set_hl(0, "TelescopeQueryFilter", { link = "WildMenu", default = true })

  -- TODO: Should we schedule this after loading shada?
  self:assert_db_entries()

  ---@param cmd_info { bang: boolean }
  vim.api.nvim_create_user_command("FrecencyValidate", function(cmd_info)
    self:validate_database(cmd_info.bang)
  end, { bang = true, desc = "Clean up DB for telescope-frecency" })

  if self.config.auto_validate then
    self:validate_database()
  end

  vim.api.nvim_create_user_command("FrecencyMigrateDB", function()
    self:migrate_database()
  end, { desc = "Migrate DB telescope-frecency to native code" })

  local group = vim.api.nvim_create_augroup("TelescopeFrecency", {})
  vim.api.nvim_create_autocmd({ "BufWinEnter", "BufWritePost" }, {
    desc = "Update database for telescope-frecency",
    group = group,
    ---@param args { buf: integer }
    callback = function(args)
      self:register(args.buf)
    end,
  })
end

---@param opts FrecencyPickerOptions?
---@return nil
function Frecency:start(opts)
  local start = os.clock()
  log.debug "Frecency:start"
  opts = opts or {}
  self.picker = Picker.new(self.database, self.entry_maker, self.fs, self.recency, {
    default_workspace_tag = self.config.default_workspace,
    editing_bufnr = vim.api.nvim_get_current_buf(),
    filter_delimiter = self.config.filter_delimiter,
    initial_workspace_tag = opts.workspace,
    show_unindexed = self.config.show_unindexed,
    workspaces = self.config.workspaces,
  })
  self.picker:start(vim.tbl_extend("force", self.config, opts))
  log.debug(("Frecency:start picker:start takes %f seconds"):format(os.clock() - start))
end

---@param findstart 1|0
---@param base string
---@return integer|''|string[]
function Frecency:complete(findstart, base)
  return self.picker:complete(findstart, base)
end

---@private
---@return nil
function Frecency:assert_db_entries()
  if self.database:has_entry() then
    return
  elseif not self.config.use_sqlite and sqlite_module.can_use then
    local sqlite = Sqlite.new(self.fs, { root = self.config.db_root })
    if sqlite:has_entry() then
      self:migrate_database()
      return
    end
  end
  self.database:insert_files(vim.v.oldfiles)
  self:notify("Imported %d entries from oldfiles.", #vim.v.oldfiles)
end

---@private
---@param force boolean?
---@return nil
function Frecency:validate_database(force)
  local unlinked = self.database:unlinked_entries()
  if #unlinked == 0 or (not force and #unlinked < self.config.db_validate_threshold) then
    return
  end
  local function remove_entries()
    self.database:remove_files(unlinked)
    self:notify("removed %d missing entries.", #unlinked)
  end
  if force and not self.config.db_safe_mode then
    remove_entries()
    return
  end
  vim.ui.select({ "y", "n" }, {
    prompt = self:message("remove %d entries from SQLite3 database?", #unlinked),
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
---@param datetime string? ISO8601 format string
function Frecency:register(bufnr, datetime)
  local path = vim.api.nvim_buf_get_name(bufnr)
  if self.buf_registered[bufnr] or not self.fs:is_valid_path(path) then
    return
  end
  self.database:update(path, self.recency.config.max_count, datetime)
  self.buf_registered[bufnr] = true
end

---@param to_sqlite boolean?
---@return nil
function Frecency:migrate_database(to_sqlite)
  local prompt = to_sqlite and "migrate the DB into SQLite from native code?"
    or "migrate the DB into native code from SQLite?"
  vim.ui.select({ "y", "n" }, {
    prompt = prompt,
    ---@param item "y"|"n"
    ---@return string
    format_item = function(item)
      return item == "y" and "Yes, Migrate it." or "No. Do nothing."
    end,
  }, function(item)
    if item == "n" then
      self:notify "migration aborted"
      return
    elseif to_sqlite then
      if sqlite_module.can_use then
        self.migrator:to_sqlite()
      else
        self:error "sqlite.lua is unavailable"
        return
      end
    else
      self.migrator:to_v1()
    end
    self:notify "Migration is finished successfully. You can remove sqlite.lua from dependencies."
  end)
end

---@private
---@param fmt string
---@param ... any?
---@return string
function Frecency:message(fmt, ...)
  return ("[Telescope-Frecency] " .. fmt):format(unpack { ... })
end

---@private
---@param fmt string
---@param ... any?
---@return nil
function Frecency:notify(fmt, ...)
  vim.notify(self:message(fmt, ...))
end

---@private
---@param fmt string
---@param ... any?
---@return nil
function Frecency:warn(fmt, ...)
  vim.notify(self:message(fmt, ...), vim.log.levels.WARN)
end

---@private
---@param fmt string
---@param ... any?
---@return nil
function Frecency:error(fmt, ...)
  vim.notify(self:message(fmt, ...), vim.log.levels.ERROR)
end

return Frecency

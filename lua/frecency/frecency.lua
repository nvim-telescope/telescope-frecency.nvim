local Database = require "frecency.database"
local EntryMaker = require "frecency.entry_maker"
local FS = require "frecency.fs"
local Finder = require "frecency.finder"
local Picker = require "frecency.picker"
local Recency = require "frecency.recency"

---@class Frecency
---@field config FrecencyConfig
---@field picker FrecencyPicker
---@field private buf_registered table<integer, boolean> flag to indicate the buffer is registered to the database.
---@field private database FrecencyDatabase
---@field private fs FrecencyFS
---@field private recency FrecencyRecency
local Frecency = {}

---@class FrecencyConfig
---@field auto_validate boolean?
---@field db_root string?
---@field db_safe_mode boolean?
---@field db_validate_threshold? integer
---@field default_workspace string?
---@field disable_devicons boolean?
---@field filter_delimiter string?
---@field ignore_patterns string[]?
---@field show_filter_column boolean|string[]|nil
---@field show_scores boolean?
---@field show_unindexed boolean?
---@field workspaces table<string, string>?

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
    show_filter_column = true,
    show_scores = false,
    show_unindexed = true,
    workspaces = {},
  }, opts or {})
  local self = setmetatable({ buf_registered = {}, config = config }, { __index = Frecency })--[[@as Frecency]]
  self.fs = FS.new { ignore_patterns = config.ignore_patterns }
  self.database = Database.new(self.fs, { root = config.db_root })
  local entry_maker = EntryMaker.new(self.fs, {
    show_filter_column = config.show_filter_column,
    show_scores = config.show_scores,
  })
  local finder = Finder.new(entry_maker, self.fs)
  self.recency = Recency.new()
  self.picker = Picker.new(self.database, finder, self.fs, self.recency, {
    default_workspace = config.default_workspace,
    filter_delimiter = config.filter_delimiter,
    show_unindexed = config.show_unindexed,
    workspaces = config.workspaces,
  })
  return self
end

function Frecency:setup()
  -- TODO: Should we schedule this after loading shada?
  if not self.database:has_entry() then
    self.database:insert_files(vim.v.oldfiles)
    self:notify("Imported %d entries from oldfiles.", #vim.v.oldfiles)
  end

  ---@param cmd_info { bang: boolean }
  vim.api.nvim_create_user_command("FrecencyValidate", function(cmd_info)
    self:validate_database(cmd_info.bang)
  end, { bang = true, desc = "Clean up DB for telescope-frecency" })

  if self.config.auto_validate then
    self:validate_database()
  end

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

---@private
---@param bufnr integer
---@param datetime string? ISO8601 format string
function Frecency:register(bufnr, datetime)
  local path = vim.api.nvim_buf_get_name(bufnr)
  if self.buf_registered[bufnr] or not self.fs:is_valid_path(path) then
    return
  end
  local id, inserted = self.database:upsert_files(path)
  self.database:insert_timestamps(id, datetime)
  self.database:trim_timestamps(id, self.recency.config.max_count)
  if inserted then
    self.picker:discard_results()
  end
  self.buf_registered[bufnr] = true
end

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

return Frecency

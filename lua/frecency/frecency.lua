local Database = require "frecency.database"
local FS = require "frecency.fs"
local Picker = require "frecency.picker"
local Recency = require "frecency.recency"
local log = require "frecency.log"

---@class Frecency
---@field config FrecencyConfig
---@field picker FrecencyPicker
---@field private database FrecencyDatabase
---@field private fs FrecencyFS
---@field private recency FrecencyRecency
---@field private buf_registered table<integer, boolean> flag to indicate the buffer is registered to the database.
local Frecency = {}

---@class FrecencyConfig
---@field auto_validate boolean
---@field db_root string
---@field db_safe_mode boolean
---@field default_workspace string?
---@field disable_devicons boolean
---@field filter_delimiter string
---@field ignore_patterns string[]
---@field show_filter_column boolean|string[]
---@field show_scores boolean
---@field show_unindexed boolean
---@field workspaces table<string, string>

---@param opts FrecencyConfig?
---@return Frecency
Frecency.new = function(opts)
  local self = setmetatable({
    config = vim.tbl_extend("force", {
      auto_validate = true,
      db_root = vim.fn.stdpath "data",
      db_safe_mode = true,
      default_workspace = nil,
      disable_devicons = false,
      filter_delimiter = ":",
      ignore_patterns = { "*.git/*", "*/tmp/*", "term://*" },
      show_filter_column = true,
      show_scores = false,
      show_unindexed = true,
      workspaces = {},
    }, opts or {}),
    buf_registered = {},
  }, { __index = Frecency })--[[@as Frecency]]
  self.database = Database.new {
    auto_validate = self.config.auto_validate,
    root = self.config.db_root,
    safe_mode = self.config.db_safe_mode,
  }
  self.fs = FS.new { ignore_patterns = self.config.ignore_patterns }
  self.recency = Recency.new()
  self.picker = Picker.new(self.database, self.recency, {
    default_workspace = self.config.default_workspace,
    filter_delimiter = self.config.filter_delimiter,
    fs = self.fs,
    show_filter_column = self.config.show_filter_column,
    show_scores = self.config.show_scores,
    show_unindexed = self.config.show_unindexed,
    workspaces = self.config.workspaces,
  })
  return self
end

function Frecency:setup()
  -- TODO: Should we schedule this after loading shada?
  if not self.database:has_entry() then
    self.database:insert_files(vim.v.oldfiles)
    log:info("Imported %d entries from oldfiles.", #vim.v.oldfiles)
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
function Frecency:register(bufnr)
  local path = vim.api.nvim_buf_get_name(bufnr)
  if self.buf_registered[bufnr] or not self.fs:is_valid_path(path) then
    return
  end
  local id, inserted = self.database:upsert_files(path)
  self.database:insert_timestamps(id)
  self.database:trim_timestamps(id, self.recency.config.max_count)
  if inserted then
    self.picker:discard_results()
  end
  self.buf_registered[bufnr] = true
end

return Frecency

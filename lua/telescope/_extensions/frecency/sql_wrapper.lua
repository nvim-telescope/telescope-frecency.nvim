local util    = require("telescope._extensions.frecency.util")
local vim = vim

local has_sql, sql = pcall(require, "sql")
if not has_sql then
  error("This plugin requires sql.nvim (https://github.com/tami5/sql.nvim)")
end

-- TODO: pass in max_timestamps from db.lua
local MAX_TIMESTAMPS = 10


-- TODO: replace at least SELECT evals with db:select()
local queries = {
  file_add_entry                = "INSERT INTO files (path, count) values(:path, 1);",
  file_delete_entry             = "DELETE FROM files WHERE id == :id;",
  file_update_counter           = "UPDATE files SET count = count + 1 WHERE path == :path;",
  timestamp_add_entry           = "INSERT INTO timestamps (file_id, timestamp) values(:file_id, julianday('now'));",
  timestamp_delete_before_id    = "DELETE FROM timestamps WHERE id < :id and file_id == :file_id;",
  timestamp_delete_with_file_id = "DELETE FROM timestamps WHERE file_id == :file_id;",
  get_all_filepaths             = "SELECT * FROM files;",
  get_all_timestamp_ages        = "SELECT id, file_id, CAST((julianday('now') - julianday(timestamp)) * 24 * 60 AS INTEGER) AS age FROM timestamps;",
  get_timestamp_ids_for_file    = "SELECT id FROM timestamps WHERE file_id == :file_id;",
}

-- local ignore_patterns = {
-- }

--

local M = {}
M.queries = queries

function M:new()
  local o = {}
  setmetatable(o, self)
  self.__index = self
  self.db = nil

  return o
end

function M:bootstrap(opts)
  opts = opts or {}

  if self.db then
    print("sql wrapper already initialised")
    return
  end

  self.max_entries = opts.max_entries or 2000

  -- create the db if it doesn't exist
  local db_root = opts.docs_root or vim.fn.stdpath('data')
  local db_filename = db_root .. "/file_frecency.sqlite3"
  self.db = sql.open(db_filename)
  if not self.db then
    print("error")
    return
  end

  -- create tables if they don't exist
  self.db:create("files", {
    ensure = true,
    id     = {"INTEGER", "PRIMARY", "KEY"},
    count  = "INTEGER",
    path   = "TEXT"
  })
  self.db:create("timestamps", {
    ensure    = true,
    id        = {"INTEGER", "PRIMARY", "KEY"},
    file_id   = "INTEGER",
    count     = "INTEGER",
    timestamp = "REAL"
    -- FOREIGN KEY(file_id)  REFERENCES files(id)
  })
  self.db:close()

end


function M:do_eval(query, params)
  local res

  self.db:with_open(function(db) res = db:eval(query, params) end)
  if res == true then res = {} end -- cater for eval returning true on empty set
  return res
end

function M:get_filepath_row_id(filepath)
  local res
  self.db:with_open(function(db) res = db:select("files", { where = { path = filepath}}) end)
  return not vim.tbl_isempty(res) and res[1].id or nil
end

function M:update(filepath)
  local filestat = util.fs_stat(filepath)
  if (vim.tbl_isempty(filestat) or
      filestat.exists       == false or
      filestat.isdirectory  == true) then
      return end

  -- create entry if it doesn't exist
  local file_id
  file_id = self:get_filepath_row_id(filepath)
  if not file_id then
    self:do_eval(queries.file_add_entry, { path = filepath })
    file_id = self:get_filepath_row_id(filepath)
  else
  -- ..or update existing entry
    self:do_eval(queries.file_update_counter, { path = filepath })
  end

  -- register timestamp for this update
  self:do_eval(queries.timestamp_add_entry, { file_id = file_id })

  -- trim timestamps to MAX_TIMESTAMPS per file (there should be up to MAX_TS + 1 at this point)
  local timestamps = self:do_eval(queries.get_timestamp_ids_for_file, { file_id = file_id })
  local trim_at = timestamps[(#timestamps - MAX_TIMESTAMPS) + 1]
  if trim_at then
    self:do_eval(queries.timestamp_delete_before_id, { id = trim_at.id, file_id = file_id })
  end
end

function M:validate()
end

return M

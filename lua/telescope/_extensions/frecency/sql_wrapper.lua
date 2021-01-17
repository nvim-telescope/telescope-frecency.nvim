local util    = require("telescope._extensions.frecency.util")
local vim = vim

local has_sql, sql = pcall(require, "sql")
if not has_sql then
  error("This plugin requires sql.nvim (https://github.com/tami5/sql.nvim)")
end

-- TODO: pass in max_timestamps from db.lua
local MAX_TIMESTAMPS = 10

--

local M = {}

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

  local first_run = false
  if not self.db:exists("files") then
    first_run = true
    -- create tables if they don't exist
    self.db:create("files", {
      id     = {"INTEGER", "PRIMARY", "KEY"},
      count  = "INTEGER",
      path   = "TEXT"
    })
    self.db:create("timestamps", {
      id        = {"INTEGER", "PRIMARY", "KEY"},
      file_id   = "INTEGER",
      timestamp = "REAL"
      -- FOREIGN KEY(file_id)  REFERENCES files(id)
    })
  end

  self.db:close()
  return first_run
end

--

function M:do_transaction(t, params)
  -- print(vim.inspect(t))
  -- print(vim.inspect(params))
  return self.db:with_open(function(db)
    local case = {
      [1] = function() return db:select(t.cmd_data, params) end,
      [2] = function() return db:insert(t.cmd_data, params) end,
      [3] = function() return db:delete(t.cmd_data, params) end,
      [4] = function() return db:eval(t.cmd_data,   params) end,
    }
    return case[t.cmd]()
  end)
end

local cmd = {
  select = 1,
  insert = 2,
  delete = 3,
  eval   = 4,
}

local queries = {
  file_add_entry = {
    cmd      = cmd.insert,
    cmd_data = "files"
  },
  file_delete_entry = {
    cmd      = cmd.delete,
    cmd_data = "files"
  },
  file_get_entries = {
    cmd      = cmd.select,
    cmd_data = "files"
  },
  file_update_counter = {
    cmd      = cmd.eval,
    cmd_data = "UPDATE files SET count = count + 1 WHERE path == :path;"
  },
  timestamp_add_entry = {
    cmd      = cmd.eval,
    cmd_data = "INSERT INTO timestamps (file_id, timestamp) values(:file_id, julianday('now'));"
  },
  timestamp_delete_entry = {
    cmd      = cmd.delete,
    cmd_data = "timestamps"
  },
  timestamp_get_all_entries = {
    cmd      = cmd.select,
    cmd_data = "timestamps",
  },
  timestamp_get_all_entry_ages = {
    cmd      = cmd.eval,
    cmd_data = "SELECT id, file_id, CAST((julianday('now') - julianday(timestamp)) * 24 * 60 AS INTEGER) AS age FROM timestamps;"
  },
  timestamp_delete_before_id = {
    cmd      = cmd.eval,
    cmd_data = "DELETE FROM timestamps WHERE id < :id and file_id == :file_id;"
  },
}

M.queries = queries

--

local function row_id(entry)
  return (not vim.tbl_isempty(entry)) and entry[1].id or nil
end

function M:update(filepath)
  local filestat = util.fs_stat(filepath)
  if (vim.tbl_isempty(filestat) or
      filestat.exists       == false or
      filestat.isdirectory  == true) then
      return end

  -- create entry if it doesn't exist
  local file_id
  file_id = row_id(self:do_transaction(queries.file_get_entries, {where = {path = filepath}}))
  if not file_id then
    self:do_transaction(queries.file_add_entry, {path = filepath, count = 1})
    file_id = row_id(self:do_transaction(queries.file_get_entries, {where = {path = filepath}}))
  else
  -- ..or update existing entry
    self:do_transaction(queries.file_update_counter, {path = filepath})
  end

  -- register timestamp for this update
  self:do_transaction(queries.timestamp_add_entry, {file_id = file_id})

  -- trim timestamps to MAX_TIMESTAMPS per file (there should be up to MAX_TS + 1 at this point)
  local timestamps = self:do_transaction(queries.timestamp_get_all_entries, {where = {file_id = file_id}})
  local trim_at = timestamps[(#timestamps - MAX_TIMESTAMPS) + 1]
  if trim_at then
    self:do_transaction(queries.timestamp_delete_before_id, {id = trim_at.id, file_id = file_id})
  end
end

function M:validate()
end

return M

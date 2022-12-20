local util    = require("telescope._extensions.frecency.util")
local vim     = vim

local has_sqlite, sqlite = pcall(require, "sqlite")
if not has_sqlite then
  error("This plugin requires sqlite.lua (https://github.com/tami5/sqlite.lua) " .. tostring(sqlite))
end

-- TODO: pass in max_timestamps from db.lua
local MAX_TIMESTAMPS = 10

local db_table = {}
db_table.files       = "files"
db_table.timestamps  = "timestamps"
db_table.workspaces  = "workspaces"
--

-- TODO: NEXT!
-- extend substr sorter to have modes:
-- when current string is prefixed by `:foo`, results are tag_names that come from tags/workspaces table. (if `:foo ` token is incomplete it is ignored)
-- when a complete workspace tag is matched ':foobar:', results are indexed_files filtered by if their parent_dir is a descendant of the workspace_dir
-- a recursive scan_dir() result is added to the  :foobar: filter results; any non-indexed_files are given a score of zero, and are alphabetically sorted below the indexed_results

-- make tab completion for tab_names in insert mode`:foo|` state: cycles through available options

local M = {}

function M:new()
  local o = {}
  setmetatable(o, self)
  self.__index = self
  self.db = nil

  return o
end

function M:bootstrap(db_root)
  if self.db then return end

  -- opts = opts or {}
  -- self.max_entries = opts.max_entries or 2000

  -- create the db if it doesn't exist
  db_root = db_root or vim.fn.stdpath('data')
  local db_filename = db_root .. "/file_frecency.sqlite3"
  self.db = sqlite:open(db_filename)
  if not self.db then
    vim.notify("Telescope-Frecency: error in opening DB", vim.log.levels.ERROR)
    return
  end

  local first_run = false
  if not self.db:exists(db_table.files) then
    first_run = true
    -- create tables if they don't exist
    self.db:create(db_table.files, {
      id           = {"INTEGER", "PRIMARY", "KEY"},
      count        = "INTEGER",
      path         = "TEXT"
    })
    self.db:create(db_table.timestamps, {
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
  file_get_descendant_of = {
    cmd      = cmd.eval,
    cmd_data = "SELECT * FROM files WHERE path LIKE :path"
  },
  file_add_entry = {
    cmd      = cmd.insert,
    cmd_data = db_table.files
  },
  file_delete_entry = {
    cmd      = cmd.delete,
    cmd_data = db_table.files
  },
  file_get_entries = {
    cmd      = cmd.select,
    cmd_data = db_table.files
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
    cmd_data = db_table.timestamps
  },
  timestamp_get_all_entries = {
    cmd      = cmd.select,
    cmd_data = db_table.timestamps,
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
  local has_added_entry
  if not file_id then
    self:do_transaction(queries.file_add_entry, {path = filepath, count = 1})
    file_id = row_id(self:do_transaction(queries.file_get_entries, {where = {path = filepath}}))
    has_added_entry = true
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

  return has_added_entry
end

return M

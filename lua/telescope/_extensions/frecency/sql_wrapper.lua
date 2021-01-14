local vim = vim
local uv  = vim.loop

local has_sql, sql = pcall(require, "sql")
if not has_sql then
  error("This plugin requires sql.nvim (https://github.com/tami5/sql.nvim)")
end

-- TODO: pass in max_timestamps from db.lua
local MAX_TIMESTAMPS = 10

-- TODO: prioritize files in project root!

local schemas = {[[
  CREATE TABLE IF NOT EXISTS files (
    id                    INTEGER PRIMARY KEY,
    count                 INTEGER,
    path                  TEXT
  );
]],
[[
  CREATE TABLE IF NOT EXISTS timestamps (
    id                    INTEGER PRIMARY KEY,
    file_id               INTEGER,
    timestamp             REAL,
    FOREIGN KEY(file_id)  REFERENCES files(id)
  );
]]}

local queries = {
  ["file_add_entry"]              = "INSERT INTO files (path, count) values(:path, 1);",
  ["file_update_counter"]         = "UPDATE files SET count = count + 1 WHERE path = :path;",
  ["timestamp_add_entry"]         = "INSERT INTO timestamps (file_id, timestamp) values(:file_id, julianday('now'));",
  ["timestamp_delete_before_id"]  = "DELETE FROM timestamps WHERE id < :id and file_id == :file_id;",
  ["get_all_filepaths"]           = "SELECT * FROM files;",
  ["get_all_timestamp_ages"]      = "SELECT id, file_id, CAST((julianday('now') - julianday(timestamp)) * 24 * 60 AS INTEGER) AS age FROM timestamps;",
  ["get_row"]                     = "SELECT * FROM files WHERE path == :path;",
  ["get_timestamp_ids_for_file"]  = "SELECT id FROM timestamps WHERE file_id == :file_id;",
}

-- local ignore_patterns = {
-- }

--
local function fs_stat(path)  -- TODO: move this to new file with M
  local stat = uv.fs_stat(path)
  local res  = {}
  res.exists      = stat and true or false -- TODO: this is silly
  res.isdirectory = (stat and stat.type == "directory") and true or false

  return res
end

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
  local db_root = opts.docs_root or "$XDG_DATA_HOME/nvim"
  local db_filename = db_root .. "/file_frecency.sqlite3"
  self.db = sql.open(db_filename)
  if not self.db then
    print("error")
    return
  end

  -- create tables if they don't exist
  for _, s in pairs(schemas) do
    self.db:eval(s)
  end
  self.db:close()

end

function M:do_transaction(query, params)
  if not queries[query] then
    print("invalid query_preset: " .. query )
    return
  end

  local res
  self.db:with_open(function(db) res = db:eval(queries[query], params) end)
  return res
end

function M:get_row_id(filepath)
  local result = self:do_transaction('get_row', { path = filepath })

  return type(result) == "table" and result[1].id or nil
end

function M:update(filepath)
  local filestat = fs_stat(filepath)
  if (vim.tbl_isempty(filestat) or
      filestat.exists       == false or
      filestat.isdirectory  == true) then
      return end

  -- create entry if it doesn't exist
  local file_id
  file_id = self:get_row_id(filepath)
  if not file_id then
    self:do_transaction('file_add_entry', { path = filepath })
    file_id = self:get_row_id(filepath)
  else
  -- ..or update existing entry
    self:do_transaction('file_update_counter', { path = filepath })
  end

  -- register timestamp for this update
  self:do_transaction('timestamp_add_entry', { file_id = file_id })

  -- trim timestamps to MAX_TIMESTAMPS per file (there should be up to MAX_TS + 1 at this point)
  local timestamps = self:do_transaction('get_timestamp_ids_for_file', { file_id = file_id })
  local trim_at = timestamps[(#timestamps - MAX_TIMESTAMPS) + 1]
  if trim_at then
    self:do_transaction('timestamp_delete_before_id', { id = trim_at.id, file_id = file_id })
  end
end

function M:validate()
end

return M

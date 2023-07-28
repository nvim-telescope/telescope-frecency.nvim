local sqlite = require "sqlite"
local log = require "frecency.log"

---@class FrecencyDatabaseConfig
---@field auto_validate boolean
---@field root string
---@field safe_mode boolean

---@class FrecencySqlite: sqlite_db
---@field files sqlite_tbl
---@field timestamps sqlite_tbl

---@class FrecencyFile
---@field count integer
---@field id integer
---@field path string
---@field score integer calculated from count and age

---@class FrecencyTimestamp
---@field age integer calculated from timestamp
---@field file_id integer
---@field id integer
---@field timestamp number

---@class FrecencyDatabaseGetFilesOptions
---@field path string?
---@field workspace string?

---@class FrecencyDatabase
---@field config FrecencyDatabaseConfig
---@field private buf_registered_flag_name string
---@field private sqlite FrecencySqlite
---@field private timestamps_age_query string
local Database = {}

---@param config FrecencyDatabaseConfig
---@return FrecencyDatabase
Database.new = function(config)
  local lib = sqlite.lib --[[@as sqlite_lib]]
  local self = setmetatable({
    config = config,
    buf_registered_flag_name = "telescope_frecency_registered",
    timestamps_age_query = lib.cast((lib.julianday() - lib.julianday "timestamp") * 24 * 60, "integer"),
  }, { __index = Database })
  self.sqlite = sqlite {
    uri = self.config.root .. "/file_frecency.sqlite3",
    files = { id = true, count = { "integer", default = 0, required = true }, path = "string" },
    timestamps = {
      id = true,
      file_id = { "integer", reference = "files.id", on_delete = "cascade" },
      timestamp = { "real", default = lib.julianday "now" },
    },
  }
  return self
end

---@return boolean
function Database:has_entry()
  return self.sqlite.files:count() > 0
end

---@param paths string[]
---@return integer
function Database:insert_files(paths)
  ---@param path string
  return self.sqlite.files:insert(vim.tbl_map(function(path)
    return { path = path, count = 0 } -- TODO: remove when sql.nvim#97 is closed
  end, paths))
end

---@param workspace string?
---@return FrecencyFile[]
function Database:get_files(workspace)
  local query = workspace and { contains = { path = { workspace .. "*" } } } or {}
  log:debug("%s", { query = query })
  return self.sqlite.files:get(query)
end

---@return FrecencyTimestamp[]
function Database:get_timestamps()
  return self.sqlite.timestamps:get { keys = { age = self.timestamps_age_query, "id", "file_id" } }
end

---@param path string
---@return integer: id of the file entry
---@return boolean: whether the entry is inserted (true) or updated (false)
function Database:upsert_files(path)
  local file = self.sqlite.files:get({ where = { path = path } })[1] --[[@as FrecencyFile?]]
  if file then
    self.sqlite.files:update { where = { id = file.id }, set = { count = file.count + 1 } }
    return file.id, false
  end
  return self.sqlite.files:insert { path = path }, true
end

---@param file_id integer
---@return integer
function Database:insert_timestamps(file_id)
  return self.sqlite.timestamps:insert { file_id = file_id }
end

---@param file_id integer
---@param max_count integer
function Database:trim_timestamps(file_id, max_count)
  local timestamps = self.sqlite.timestamps:get { where = { file_id = file_id } } --[[@as FrecencyTimestamp[] ]]
  local trim_at = timestamps[#timestamps - max_count + 1]
  if trim_at then
    self.sqlite.timestamps:remove { file_id = tostring(file_id), id = "<" .. tostring(trim_at.id) }
  end
end

return Database

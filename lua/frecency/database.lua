local sqlite = require "sqlite"
local log = require "plenary.log"

---@class FrecencyDatabaseConfig
---@field root string

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
---@field private fs FrecencyFS
---@field private sqlite FrecencySqlite
local Database = {}

---@param fs FrecencyFS
---@param config FrecencyDatabaseConfig
---@return FrecencyDatabase
Database.new = function(fs, config)
  local lib = sqlite.lib --[[@as sqlite_lib]]
  local self = setmetatable(
    { config = config, buf_registered_flag_name = "telescope_frecency_registered", fs = fs },
    { __index = Database }
  )
  self.sqlite = sqlite {
    uri = self.config.root .. "/file_frecency.sqlite3",
    files = { id = true, count = { "integer", default = 1, required = true }, path = "string" },
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
  local query = workspace and { contains = { path = { workspace .. "/*" } } } or {}
  log.debug { query = query }
  return self.sqlite.files:get(query)
end

---@param datetime string? ISO8601 format string
---@return FrecencyTimestamp[]
function Database:get_timestamps(datetime)
  local lib = sqlite.lib
  local age = lib.cast((lib.julianday(datetime) - lib.julianday "timestamp") * 24 * 60, "integer")
  return self.sqlite.timestamps:get { keys = { age = age, "id", "file_id" } }
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
---@param datetime string? ISO8601 format string
---@return integer
function Database:insert_timestamps(file_id, datetime)
  return self.sqlite.timestamps:insert {
    file_id = file_id,
    timestamp = datetime and sqlite.lib.julianday(datetime) or nil,
  }
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

---@return integer[]
function Database:unlinked_entries()
  ---@param file FrecencyFile
  return self.sqlite.files:map(function(file)
    if not self.fs:is_valid_path(file.path) then
      return file.id
    end
  end)
end

---@param ids integer[]
---@return nil
function Database:remove_files(ids)
  self.sqlite.files:remove { id = ids }
end

return Database

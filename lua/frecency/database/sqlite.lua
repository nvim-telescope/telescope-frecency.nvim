local sqlite = require "frecency.sqlite"
local log = require "plenary.log"
local Path = require "plenary.path" --[[@as PlenaryPath]]

---@class FrecencySqliteDB: sqlite_db
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

---@class FrecencyDatabaseSqlite: FrecencyDatabase
---@field sqlite FrecencySqliteDB
local Sqlite = {}

---@param fs FrecencyFS
---@param config FrecencyDatabaseConfig
---@return FrecencyDatabaseSqlite
Sqlite.new = function(fs, config)
  local self = setmetatable(
    { config = config, buf_registered_flag_name = "telescope_frecency_registered", fs = fs },
    { __index = Sqlite }
  )
  self.filename = Path.new(self.config.root, "file_frecency.sqlite3").filename
  self.sqlite = setmetatable({}, {
    __index = function(this, key)
      if not rawget(this, "instance") then
        local lib = sqlite.lib
        rawset(
          this,
          "instance",
          sqlite {
            uri = self.filename,
            files = { id = true, count = { "integer", default = 1, required = true }, path = "string" },
            timestamps = {
              id = true,
              file_id = { "integer", reference = "files.id", on_delete = "cascade" },
              timestamp = { "real", default = lib.julianday "now" },
            },
          }
        )
      end
      return rawget(this, "instance")[key]
    end,
  })
  return self
end

---@return boolean
function Sqlite:has_entry()
  return self.sqlite.files:count() > 0
end

---@param paths string[]
---@return integer
function Sqlite:insert_files(paths)
  if #paths == 0 then
    return 0
  end
  ---@param path string
  return self.sqlite.files:insert(vim.tbl_map(function(path)
    return { path = path, count = 0 } -- TODO: remove when sql.nvim#97 is closed
  end, paths))
end

---@param workspace string?
---@param datetime string?
---@return FrecencyDatabaseEntry[]
function Sqlite:get_entries(workspace, datetime)
  local query = workspace and { contains = { path = { workspace .. "/*" } } } or {}
  log.debug { query = query }
  local files = self.sqlite.files:get(query) --[[@as FrecencyFile[] ]]
  local lib = sqlite.lib
  local age = lib.cast((lib.julianday(datetime) - lib.julianday "timestamp") * 24 * 60, "integer")
  local timestamps = self.sqlite.timestamps:get { keys = { age = age, "id", "file_id" } } --[[@as FrecencyTimestamp[] ]]
  ---@type table<integer,number[]>
  local age_map = {}
  for _, timestamp in ipairs(timestamps) do
    if not age_map[timestamp.file_id] then
      age_map[timestamp.file_id] = {}
    end
    table.insert(age_map[timestamp.file_id], timestamp.age)
  end
  local items = {}
  for _, file in ipairs(files) do
    table.insert(items, { path = file.path, count = file.count, ages = age_map[file.id] })
  end
  return items
end

---@param datetime string? ISO8601 format string
---@return FrecencyTimestamp[]
function Sqlite:get_timestamps(datetime)
  local lib = sqlite.lib
  local age = lib.cast((lib.julianday(datetime) - lib.julianday "timestamp") * 24 * 60, "integer")
  return self.sqlite.timestamps:get { keys = { age = age, "id", "file_id" } }
end

---@param path string
---@param count integer
---@param datetime string?
---@return nil
function Sqlite:update(path, count, datetime)
  local file = self.sqlite.files:get({ where = { path = path } })[1] --[[@as FrecencyFile?]]
  local file_id
  if file then
    self.sqlite.files:update { where = { id = file.id }, set = { count = file.count + 1 } }
    file_id = file.id
  else
    file_id = self.sqlite.files:insert { path = path }
  end
  self.sqlite.timestamps:insert {
    file_id = file_id,
    timestamp = datetime and sqlite.lib.julianday(datetime) or nil,
  }
  local timestamps = self.sqlite.timestamps:get { where = { file_id = file_id } } --[[@as FrecencyTimestamp[] ]]
  local trim_at = timestamps[#timestamps - count + 1]
  if trim_at then
    self.sqlite.timestamps:remove { file_id = tostring(file_id), id = "<" .. tostring(trim_at.id) }
  end
end

---@return integer[]
function Sqlite:unlinked_entries()
  ---@param file FrecencyFile
  return self.sqlite.files:map(function(file)
    if not self.fs:is_valid_path(file.path) then
      return file.id
    end
  end)
end

---@param ids integer[]
---@return nil
function Sqlite:remove_files(ids)
  self.sqlite.files:remove { id = ids }
end

return Sqlite

local Sqlite = require "frecency.database.sqlite"
local Native = require "frecency.database.native"
local wait = require "frecency.wait"

---@class FrecencyMigrator
---@field fs FrecencyFS
---@field recency FrecencyRecency
---@field root string
local Migrator = {}

---@param fs FrecencyFS
---@param recency FrecencyRecency
---@param root string
---@return FrecencyMigrator
Migrator.new = function(fs, recency, root)
  return setmetatable({ fs = fs, recency = recency, root = root }, { __index = Migrator })
end

---@return nil
function Migrator:to_v1()
  local native = Native.new(self.fs, { root = self.root })
  native.table = self:v1_table_from_sqlite()
  wait(function()
    native:save()
  end)
end

---@return nil
function Migrator:to_sqlite()
  local sqlite = Sqlite.new(self.fs, { root = self.root })
  local native = Native.new(self.fs, { root = self.root })
  for path, record in pairs(native.table.records) do
    local file_id = sqlite.sqlite.files:insert { path = path, count = record.count }
    sqlite.sqlite.timestamps:insert(vim.tbl_map(function(timestamp)
      return { file_id = file_id, timestamp = ('julianday(datetime(%d, "unixepoch"))'):format(timestamp) }
    end, record.timestamps))
  end
end

---@private
---@return FrecencyDatabaseNativeTable
function Migrator:v1_table_from_sqlite()
  local sqlite = Sqlite.new(self.fs, { root = self.root })
  ---@type FrecencyDatabaseNativeTable
  local tbl = { version = "v1", records = {} }
  local files = sqlite.sqlite.files:get {} --[[@as FrecencyFile[] ]]
  ---@type table<integer,string>
  local path_map = {}
  for _, file in ipairs(files) do
    tbl.records[file.path] = { count = file.count, timestamps = { 0 } }
    path_map[file.id] = file.path
  end
  -- local timestamps = sqlite.sqlite.timestamps:get { keys = { "id", "file_id", epoch = "unixepoch(timestamp)" } } --[[@as FrecencyTimestamp[] ]]
  local timestamps = sqlite.sqlite.timestamps:get {
    keys = { "id", "file_id", epoch = "cast(strftime('%s', timestamp) as integer)" },
  } --[[@as FrecencyTimestamp[] ]]
  table.sort(timestamps, function(a, b)
    return a.id < b.id
  end)
  for _, timestamp in ipairs(timestamps) do
    local path = path_map[timestamp.file_id]
    if path then
      local record = tbl.records[path]
      if record then
        if #record.timestamps == 1 and record.timestamps[1] == 0 then
          record.timestamps = {}
        end
        ---@diagnostic disable-next-line: undefined-field
        table.insert(record.timestamps, timestamp.epoch)
        if #record.timestamps > self.recency.config.max_count then
          local new_table = {}
          for i = #record.timestamps - self.recency.config.max_count + 1, #record.timestamps do
            table.insert(new_table, record.timestamps[i])
          end
          record.timestamps = new_table
        end
      end
    end
  end
  return tbl
end

return Migrator

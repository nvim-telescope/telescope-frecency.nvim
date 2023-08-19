local async = require "plenary.async" --[[@as PlenaryAsync]]

---@class FrecencyDatabaseNative: FrecencyDatabase
---@field version "v1"
---@field filename string
---@field private table FrecencyDatabaseNativeTable
local Native = {}

---@class FrecencyDatabaseNativeTable
---@field version string
---@field records table<string,FrecencyDatabaseNativeRecord>

---@class FrecencyDatabaseNativeRecord
---@field count integer
---@field timestamps integer[]

---@param fs FrecencyFS
---@param config FrecencyDatabaseConfig
---@return FrecencyDatabase
Native.new = function(fs, config)
  local self = setmetatable({ config = config, fs = fs }, { __index = Native })
  self.filename = self.config.root .. "/file_frecency.bin"
  self.table = self:load() or { version = "v1", records = {} }
  return self
end

---@return boolean
function Native:has_entry()
  return #self.table.records > 0
end

---@async
---@param paths string[]
---@return nil
function Native:insert_files(paths)
  if #paths == 0 then
    return
  end
  for _, path in ipairs(paths) do
    self.table.records[path] = { count = 1, timestamps = { 0 } }
  end
  self:save()
end

---@async
---@return string[]
function Native:unlinked_entries()
  local paths = {}
  for file in pairs(self.table.records) do
    if not self.fs:is_valid_path(file) then
      table.insert(paths, file)
    end
  end
  return paths
end

---@async
---@param paths string[]
function Native:remove_files(paths)
  for _, file in ipairs(paths) do
    self.table.records[file] = nil
  end
  self:save()
end

---@async
---@param path string
---@param count integer
---@param datetime string?
function Native:update(path, count, datetime)
  local record = self.table.records[path] and self.table.records[path] or { count = 1, timestamps = {} }
  record.count = record.count + 1
  local now = self:now(datetime)
  table.insert(record.timestamps, now)
  if #record.timestamps > count then
    local new_table = {}
    for i = #record.timestamps - count + 1, #record.timestamps do
      table.insert(new_table, record.timestamps[i])
    end
    record.timestamps = new_table
  end
  self.table.records[path] = record
  self:save()
end

---@async
---@param workspace string?
---@param datetime string?
---@return { path: string, ages: number[] }[]
function Native:get_entries(workspace, datetime)
  -- TODO: check mtime of DB and reload it
  -- self:load()
  local now = self:now(datetime)
  local items = {}
  for path, record in pairs(self.table.records) do
    if not workspace or path:find(workspace .. "/", 1, true) then
      table.insert(items, {
        path = path,
        count = record.count,
        ages = vim.tbl_map(function(v)
          return (now - v) / 60
        end, record.timestamps),
      })
    end
  end
  return items
end

---@private
---@param datetime string?
---@return integer
function Native:now(datetime)
  return datetime and vim.fn.strptime("%FT%T%z", datetime) or os.time()
end

---@async
---@private
---@return FrecencyDatabaseNativeTable?
function Native:load()
  local st = async.uv.fs_stat(self.filename)
  if not st then
    return
  end
  local fd = assert(async.uv.fs_open(self.filename, "r", tonumber("644", 8)))
  local data = async.uv.fs_read(fd, st.size)
  assert(async.uv.fs_close(fd))
  local make_records = loadstring(data)
  if not make_records then
    return
  end
  local records = make_records() --[[@as FrecencyDatabaseNativeTable]]
  if records.version == self.version then
    ---@diagnostic disable-next-line: param-type-mismatch
    return records
  end
end

---@async
---@private
---@return nil
function Native:save()
  -- TODO: lock the DB
  local f = assert(load("return " .. vim.inspect(self.table)))
  local data = string.dump(f)
  local fd = assert(async.uv.fs_open(self.filename, "w", tonumber("644", 8)))
  assert(async.uv.fs_write(fd, data))
  assert(async.uv.fs_close(fd))
end

return Native

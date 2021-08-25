local util = require "frecency.util"
local const = require "frecency.const"
local algo = require "frecency.algo"
local sql = require "sql"
local p = require "plenary.path"
local s = sql.lib

---@class FrecencyDB: SQLDatabaseExt
---@field files SQLTableExt
---@field timestamps SQLTableExt
---@field workspaces SQLTableExt
---@field config FrecencyConfig
local db = sql {
  uri = vim.fn.stdpath "data" .. "/file_frecency.sqlite3",
  files = { id = true, count = { "integer" }, path = "string" },
  timestamps = { id = true, timestamp = "real", file_id = "integer" },
}

---@class FrecencyDBConfig
---@field db_root string: default "${stdpath.data}/file_frecency.sqlite3"
---@field ignore_patterns table: extra ignore patterns: default empty
---@field safe_mode boolean: When enabled, the user will be prompted when entries > 10, default true
---@field auto_validate boolean: When this to false, stale entries will never be automatically removed, default true
db.config = {
  db_root = nil,
  ignore_patterns = {},
  safe_mode = true,
  auto_validate = true,
}

---Set database configuration
---@param config FrecencyDBConfig
db.set_config = function(config)
  db.config = vim.tbl_extend("keep", config, db.config)
end

---Initialize frecency Database. if { db.is_initialized } then skip return early.
---@return FrecencyDB
db.init = function()
  if db.is_initialized then
    return
  end

  db.db.uri = db.config.db_root and db.config.db_root or db.db.uri
  db.is_initialized = true

  ---Seed files table with oldfiles when it's empty.
  if db.files.count() == 0 then
    -- TODO: this needs to be scheduled for after shada load??
    local oldfiles = vim.api.nvim_get_vvar "oldfiles"
    for _, path in ipairs(oldfiles) do
      db.files.insert { path = path, count = 0 } -- TODO: remove when sql.nvim#97 is closed
    end
    print(("Telescope-Frecency: Imported %d entries from oldfiles."):format(#oldfiles))
  end
end

---Get timestamps with a computed filed called age.
---If file_id is nil, then get all timestamps.
---@param opts table
---- { file_id } number: id file_id corresponding to `files.id`. return all if { file_id } is nil
---- { with_age } boolean: whether to include age, default false.
---@return table { id, file_id, age }
---@overload func()
db.timestamps.get = function(opts)
  opts = opts or {}
  local where = opts.file_id and { file_id = opts.file_id } or nil
  local compute_age = opts.with_age and s.cast((s.julianday() - s.julianday "timestamp") * 24 * 60, "integer") or nil
  return db.timestamps._get { where = where, keys = { age = compute_age, "id", "file_id" } }
end

---Trim database entries
---@param file_id any
db.timestamps.trim = function(file_id)
  local timestamps = db.timestamps.get { file_id = file_id, with_age = true }
  local trim_at = timestamps[(#timestamps - const.max_timestamps) + 1]
  if trim_at then
    db.timestamps.remove { file_id = file_id, id = "<" .. trim_at.id }
  end
end

---Get file entries
---@param opts table:
---- { ws_path } string: get files with matching workspace path.
---- { show_unindexed } boolean: whether to include unindexed files, false if no ws_path is given.
---- { with_score } boolean: whether to include score in the result and sort the files by score.
---@overload func()
---@return table[]: files entries
db.files.get = function(opts)
  opts = opts or {}
  local contains = opts.ws_path and { path = { opts.ws_path .. "*" } } or nil
  local files = db.files._get { contains = contains }

  if opts.with_score then
    ---NOTE: this might get slower with big db, it might be better to query with db.get_timestamp.
    ---TODO: test the above assumption
    local timestamps = db.timestamps.get { with_age = true }
    for _, file in ipairs(files) do
      file.timestamps = util.tbl_match("file_id", file.id, timestamps)
      file.score = algo.calculate_file_score(file)
    end

    table.sort(files, function(a, b)
      return a.score > b.score
    end)
  end

  if opts.ws_path and opts.show_unindexed then
    util.include_unindexed(files, opts.ws_path)
  end

  return files
end

---Insert or update a given path
---@param path string
---@return number: row id
db.files.insert_or_update = function(path)
  local entry = (db.files.where { path = path } or {})
  local file_id = entry.id

  if file_id then
    db.files.update { where = { id = file_id }, set = { count = entry.count + 1 } }
  else
    file_id = db.files.insert { path = path, count = 0 } -- TODO: remove when sql.nvim#97 is closed
  end

  return file_id
end

-- db.files.insert_or_update ""
---Add or update file path
---@param path string|nil: path to file or use current
---@overload func()
db.update = function(path)
  path = path or vim.fn.expand "%:p"
  vim.b.telescope_frecency_registered = false
  if vim.b.telescope_frecency_registered or util.path_invalid(path, db.ignore_patterns) then
    print "ignoring autocmd"
    return
  end
  -- In case that it isn't initialize yet
  db.init()
  --- Insert or update path
  local file_id = db.files.insert_or_update(path)
  --- Register timestamp for this update.
  db.timestamps.insert { file_id = file_id, timestamp = s.julianday "now" }
  --- Trim timestamps to max_timestamps per file
  db.timestamps.trim(file_id)
end

---Remove unlinked file entries, along with timestamps linking to it.
---@param entries table[]|table|nil: if nil it will remove all entries
---@param silent boolean: whether to notify user on changes made, default false
db.remove = function(entries, silent)
  if type(entries) == "nil" then
    local count = db.files.count()
    db.files.remove()
    db.timestamps.remove()
    if not vim.F.if_nil(silent, false) then
      print(("Telescope-frecency: removed all entries. number of entries removed %d ."):format(count))
    end
    return
  end

  entries = (entries[1] and entries[1].id) and entries or { entries }
  for _, entry in pairs(entries) do
    db.files.remove { id = entry.id }
    db.timestamps.remove { file_id = entry.id }
  end

  if not vim.F.if_nil(silent, false) then
    print(("Telescope-frecency: removed %d missing entries."):format(#entries))
  end
end

---Remove file entries that no longer exists.
db.validate = function()
  print "running validate"
  local threshold = const.db_remove_safety_threshold
  local unlinked = db.files.map(function(entry)
    local invalid = (not util.path_exists(entry.path) or util.path_is_ignored(entry.path, db.ignore_patterns))
    return invalid and entry or nil
  end)

  local confirmed = (#unlinked > threshold and db.safe_mode) and util.confirm_deletion(#unlinked) or not safe_mode
  if #unlinked > 0 then
    if confirmed then
      db.remove(unlinked)
    else
      util.abort_remove_unlinked_files()
    end
  end
end

return db

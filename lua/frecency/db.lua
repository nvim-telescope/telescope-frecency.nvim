local util = require "frecency.util"
local const = require "frecency.const"
local algo = require "frecency.algo"

local ok, sql = pcall(require, "sql")
if not ok then
  error "ERROR: frecency-telescope.nvim: sql.nvim (https://github.com/tami5/sql.nvim) is not found. Please install"
  return
end
local s = sql.lib

---@class FrecencyDB: SQLDatabaseExt
---@field files SQLTableExt
---@field timestamps SQLTableExt
---@field workspaces SQLTableExt
---@field config FrecencyConfig
local db = sql {
  uri = vim.fn.stdpath "data" .. "/file_frecency.sqlite3",
  files = { id = true, count = { "integer", default = 0 }, path = "string" },
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

---Initialize frecency Database
---@param config FrecencyDBConfig
---@overload func()
---@return FrecencyDB
db.init = function(config)
  config = config or {}
  db.db.uri = config.db_root and config.db_root or db.db.uri
  db.config = config and db.set_config(config) or db.config
  db.db:init()
  db.is_initialized = db.db.is_initialized ---TODO: remove when sql.nvim@#93 is fixed

  ---Use oldfiles on first run.
  if db.files:count() == 0 then
    -- TODO: this needs to be scheduled for after shada load??
    local oldfiles = vim.api.nvim_get_vvar "oldfiles"
    for _, path in pairs(oldfiles) do
      db.files.insert { path = path }
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
db.get_timestamps = function(opts)
  opts = opts or {}
  local where = opts.file_id and { file_id = opts.file_id } or nil
  local compute_age = opts.with_age and s.cast((s.julianday() - s.julianday "timestamp") * 24 * 60, "integer") or nil
  return db.timestamps.get { where = where, keys = { age = compute_age, "id", "file_id" } }
end

---Get file entries
---@param opts table:
---- { ws_path } string: get files with matching workspace path.
---- { show_unindexed } boolean: whether to include unindexed files, false if no ws_path is given.
---- { with_score } boolean: whether to include score in the result and sort the files by score.
---@overload func()
---@return table[]: files entries
db.get_files = function(opts)
  opts = opts or {}
  local contains = opts.ws_path and { path = { opts.ws_path .. "*" } } or nil
  local files = db.files.get { contains = contains }

  if opts.ws_path and opts.show_unindexed then
    util.include_unindexed(files, opts.ws_path)
  end

  if opts.with_score then
    ---NOTE: this might get slower with big db, it might be better to query with db.get_timestamp.
    ---TODO: test the above assumption
    local timestamps = db.get_timestamps { with_age = true }
    for _, file in ipairs(files) do
      file.timestamps = util.tbl_match("file_id", file.id, timestamps)
      file.score = algo.calculate_file_score(file)
    end
    table.sort(files, function(a, b)
      return a.score > b.score
    end)
  end

  return files
end

---Add or update file path
---@param path string: path to file or use current
db.update = function(path)
  if not util.path_invalid(path) then
    ---Get entry for current path.
    local entry = (db.files.where { path = path } or {})
    local file_id = not entry.id and db.files.insert { path = path } or entry.id

    ---Update count if entry.id is non-nil.
    if entry.id then
      db.files.update { where = { id = entry.id }, set = { count = entry.count + 1 } }
    end

    ---Register timestamp for this update.
    db.timestamps.insert { file_id = file_id, timestamp = s.julianday "now" }

    ---Trim timestamps to max_timestamps per file
    local timestamps = db.get_timestamps { file_id = file_id, with_age = true }
    local trim_at = timestamps[(#timestamps - const.max_timestamps) + 1]
    if trim_at then
      db.timestamps.remove { file_id = file_id, id = "<" .. trim_at.id }
    end
  end
end

---Remove unlinked file entries, along with timestamps linking to it.
---@param entries table[]|nil
---@param silent boolean: whether to notify user on changes made, default false
db.remove = function(entries, silent)
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
---@param safe_mode boolean: whether to take user input if to be removed exceed
db.validate = function(safe_mode)
  safe_mode = vim.F.if_nil(safe_mode, false)
  local threshold = const.db_remove_safety_threshold
  local unlinked = db.files.map(function(entry)
    return (not util.fs_stat(entry.path).exists or util.file_is_ignored(entry.path)) and entry or nil
  end)

  local confirmed = (#unlinked > threshold and safe_mode) and util.confirm_deletion(#unlinked) or not safe_mode
  if #unlinked > 0 then
    if confirmed then
      db.remove(unlinked)
    else
      util.abort_remove_unlinked_files()
    end
  end
end

---Register current buffer path.
---@see db.update
---@param path string: file path.
db.register = function()
  local path = vim.fn.expand "%:p"
  local registered = vim.b.telescope_frecency_registered
  local skip = (not registered and (util.fs_stat(path).exists or util.file_is_ignored(path)))
  if skip or util.string_isempty(path) then
    return
  else
    vim.b.telescope_frecency_registered = 1
    if not db.is_initialized then
      db.init()
    end
    db.update(path)
  end
end

return db

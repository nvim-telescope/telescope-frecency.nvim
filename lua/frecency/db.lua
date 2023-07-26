local util = require "frecency.util"
local const = require "frecency.const"
local algo = require "frecency.algo"
local sqlite = require "sqlite"
local p = require "plenary.path"
local s = sqlite.lib
local log = require "frecency.log"

---@class FrecencyDBConfig
---@field db_root string: default "${stdpath.data}"
---@field ignore_patterns table: extra ignore patterns: default empty
---@field safe_mode boolean: When enabled, the user will be prompted when entries > 10, default true
---@field auto_validate boolean: When this to false, stale entries will never be automatically removed, default true

---@class FrecencyDB
---@field sqlite FrecencySqlite
---@field config FrecencyConfig
local db = {
  config = {
    db_root = vim.fn.stdpath "data",
    ignore_patterns = {},
    db_safe_mode = true,
    auto_validate = true,
  },
}

---Set database configuration
---@param config FrecencyDBConfig
function db.set_config(config)
  db.config = vim.tbl_extend("keep", config, db.config)
  db.sqlite = sqlite {
    uri = db.config.db_root .. "/file_frecency.sqlite3",
    files = {
      id = true,
      count = { "integer", default = 0, required = true },
      path = "string",
    },
    timestamps = {
      id = true,
      timestamp = { "real", default = s.julianday "now" },
      file_id = { "integer", reference = "files.id", on_delete = "cascade" },
    },
  }
end

---Get timestamps with a computed filed called age.
---If file_id is nil, then get all timestamps.
---@param opts table
---- { file_id } number: id file_id corresponding to `files.id`. return all if { file_id } is nil
---- { with_age } boolean: whether to include age, default false.
---@return table { id, file_id, age }
---@overload func()
function db.get_timestamps(opts)
  opts = opts or {}
  local where = opts.file_id and { file_id = opts.file_id } or nil
  local compute_age = opts.with_age and s.cast((s.julianday() - s.julianday "timestamp") * 24 * 60, "integer") or nil
  return db.sqlite.timestamps:__get { where = where, keys = { age = compute_age, "id", "file_id" } }
end

---Trim database entries
---@param file_id any
function db.trim_timestamps(file_id)
  local timestamps = db.get_timestamps { file_id = file_id, with_age = true }
  local trim_at = timestamps[(#timestamps - const.max_timestamps) + 1]
  if trim_at then
    db.sqlite.timestamps:remove { file_id = file_id, id = "<" .. trim_at.id }
  end
end

---Get file entries
---@param opts table:
---- { ws_path } string: get files with matching workspace path.
---- { show_unindexed } boolean: whether to include unindexed files, false if no ws_path is given.
---- { with_score } boolean: whether to include score in the result and sort the files by score.
---@overload func()
---@return table[]: files entries
function db.get_files(opts)
  opts = opts or {}
  local query = {}
  if opts.ws_path then
    query.contains = { path = { opts.ws_path .. "*" } }
  elseif opts.path then
    query.where = { path = opts.path }
  end
  local files = db.sqlite.files:__get(query)

  if vim.F.if_nil(opts.with_score, true) then
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

  if opts.ws_path and opts.show_unindexed then
    util.include_unindexed(files, opts.ws_path)
  end

  return files
end
---Insert or update a given path
---@param path string
---@return number: row id
---@return boolean: true if it has inserted
function db.insert_or_update_files(path)
  local entry = (db.get_files({ path = path })[1] or {})
  local file_id = entry.id
  local has_added_entry = not file_id

  if file_id then
    db.sqlite.files:update { where = { id = file_id }, set = { count = entry.count + 1 } }
  else
    file_id = db.sqlite.files:insert { path = path }
  end
  return file_id, has_added_entry
end

---Add or update file path
---@param path string|nil: path to file or use current
---@return boolean: true if it has added an entry
---@overload func()
function db.update(path)
  path = path or vim.fn.expand "%:p"
  if vim.b.telescope_frecency_registered or util.path_invalid(path, db.ignore_patterns) then
    -- print "ignoring autocmd"
    return
  else
    vim.b.telescope_frecency_registered = 1
  end
  --- Insert or update path
  local file_id, has_added_entry = db.insert_or_update_files(path)
  --- Register timestamp for this update.
  db.sqlite.timestamps:insert { file_id = file_id }
  --- Trim timestamps to max_timestamps per file
  db.trim_timestamps(file_id)
  return has_added_entry
end

---Remove unlinked file entries, along with timestamps linking to it.
---@param entries table[]|table|nil: if nil it will remove all entries
---@param silent boolean: whether to notify user on changes made, default false
function db.remove(entries, silent)
  if type(entries) == "nil" then
    local count = db.sqlite.files:count()
    db.sqlite.files:remove()
    if not vim.F.if_nil(silent, false) then
      vim.notify(("Telescope-frecency: removed all entries. number of entries removed %d ."):format(count))
    end
    return
  end

  entries = (entries[1] and entries[1].id) and entries or { entries }

  for _, entry in pairs(entries) do
    db.sqlite.files:remove { id = entry.id }
  end

  if not vim.F.if_nil(silent, false) then
    vim.notify(("Telescope-frecency: removed %d missing entries."):format(#entries))
  end
end

---Remove file entries that no longer exists.
function db.validate(opts)
  opts = opts or {}

  -- print "running validate"
  local threshold = const.db_remove_safety_threshold
  local unlinked = db.sqlite.files:map(function(entry)
    local invalid = (not util.path_exists(entry.path) or util.path_is_ignored(entry.path, db.ignore_patterns))
    return invalid and entry or nil
  end)

  if #unlinked > 0 then
    if opts.force or not db.config.db_safe_mode or (#unlinked > threshold and util.confirm_deletion(#unlinked)) then
      db.remove(unlinked)
    elseif not opts.auto then
      util.abort_remove_unlinked_files()
    end
  end
end

return db

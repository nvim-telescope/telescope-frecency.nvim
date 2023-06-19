local uv = vim.loop
local const = require "frecency.const"
local Path = require "plenary.path"

local util = {}

-- stolen from penlight

---escape any Lua 'magic' characters in a string
util.escape = function(str)
  return (str:gsub("[%-%.%+%[%]%(%)%$%^%%%?%*]", "%%%1"))
end

util.string_isempty = function(str)
  return str == nil or str == ""
end

util.filemask = function(mask)
  mask = util.escape(mask)
  return "^" .. mask:gsub("%%%*", ".*"):gsub("%%%?", ".") .. "$"
end

util.path_is_ignored = function(filepath, ignore_patters)
  local i = ignore_patters and vim.tbl_flatten { ignore_patters, const.ignore_patterns } or const.ignore_patterns
  local is_ignored = false
  for _, pattern in ipairs(i) do
    if filepath:find(util.filemask(pattern)) ~= nil then
      is_ignored = true
      goto continue
    end
  end

  ::continue::
  return is_ignored
end

util.path_exists = function(path)
  return Path:new(path):exists()
end

util.path_invalid = function(path, ignore_patterns)
  local p = Path:new(path)
  if
    util.string_isempty(path)
    or (not p:is_file())
    or (not p:exists())
    or util.path_is_ignored(path, ignore_patterns)
  then
    return true
  else
    return false
  end
end

util.confirm_deletion = function(num_of_entries)
  local question = "Telescope-Frecency: remove %d entries from SQLite3 database?"
  return vim.fn.confirm(question:format(num_of_entries), "&Yes\n&No", 2) == 1
end

util.abort_remove_unlinked_files = function()
  ---TODO: refactor all messages to a lua file. alarts.lua?
  vim.notify "TelescopeFrecency: validation aborted."
end

util.tbl_match = function(field, val, tbl)
  return vim.tbl_filter(function(t)
    return t[field] == val
  end, tbl)
end

---Wrappe around Path:new():make_relative
---@return string
util.path_relative = function(path, cwd)
  return Path:new(path):make_relative(cwd)
end

---Given a filename, check if there's a buffer with the given name.
---@return boolean
util.buf_is_loaded = function(filename)
  return vim.api.nvim_buf_is_loaded(vim.fn.bufnr(filename))
end

util.include_unindexed = function(files, ws_path)
  local is_indexed = {}
  for _, item in ipairs(files) do
    is_indexed[item.path] = true
  end

  local scan_opts = {
    respect_gitignore = true,
    depth = 100,
    hidden = true,
    search_pattern = function(file)
      return not is_indexed[file]
    end,
  }

  -- TODO: make sure scandir unindexed have opts.ignore_patterns applied
  -- TODO: make filters handle mulitple directories
  local unindexed_files = require("plenary.scandir").scan_dir(ws_path, scan_opts)
  for _, file in pairs(unindexed_files) do
    if not util.path_is_ignored(file) then -- this causes some slowdown on large dirs
      table.insert(files, { id = 0, path = file, count = 0, directory_id = 0, score = 0 })
    end
  end
end

return util

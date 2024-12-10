local config = require "frecency.config"
local os_util = require "frecency.os_util"
local log = require "frecency.log"
local lazy_require = require "frecency.lazy_require"
local Path = lazy_require "plenary.path" --[[@as FrecencyPlenaryPath]]
local async = lazy_require "plenary.async" --[[@as FrecencyPlenaryAsync]]
local scandir = lazy_require "plenary.scandir"
local uv = vim.uv or vim.loop

---@class FrecencyFS
local M = {
  os_homedir = assert(uv.os_homedir()),
}

-- TODO: make this configurable
local SCAN_DEPTH = 100

---@param path string
---@return boolean
function M.is_ignored(path)
  return vim.iter(config.ignore_regexes()):any(function(regex)
    return not not path:find(regex)
  end)
end

---@async
---@param path? string
---@return boolean
function M.is_valid_path(path)
  if not path then
    return false
  end
  local err, st = async.uv.fs_stat(path)
  return not err and st.type == "file" and not M.is_ignored(path)
end

---@param path string
---@return function
function M.scan_dir(path)
  log.debug { path = path }
  local gitignore = M.make_gitignore(path)
  return coroutine.wrap(function()
    for name, type in
      vim.fs.dir(path, {
        depth = SCAN_DEPTH,
        skip = function(dirname)
          if M.is_ignored(os_util.join_path(path, dirname)) then
            return false
          end
        end,
      })
    do
      local fullpath = os_util.join_path(path, name)
      if type == "file" and not M.is_ignored(fullpath) and gitignore({ path }, fullpath) then
        coroutine.yield(name)
      end
    end
  end)
end

---@param path string
---@return string
function M.relative_from_home(path)
  return Path:new(path):make_relative(M.os_homedir)
end

---@type table<string,string>
local with_sep = {}

---@param path string
---@param base? string
---@return boolean
function M.starts_with(path, base)
  if not base then
    return true
  end
  if not with_sep[base] then
    with_sep[base] = base .. (base:sub(#base) == Path.path.sep and "" or Path.path.sep)
  end
  return path:find(with_sep[base], 1, true) == 1
end

---@async
---@param path string
---@return boolean
function M.exists(path)
  return not (async.uv.fs_stat(path))
end

---@private
---@param basepath string
---@return fun(base_paths: string[], entry: string): boolean
function M.make_gitignore(basepath)
  return scandir.__make_gitignore { basepath } or function(_, _)
    return true
  end
end

return M

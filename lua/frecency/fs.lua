local config = require "frecency.config"
local os_util = require "frecency.os_util"
local log = require "frecency.log"
local lazy_require = require "frecency.lazy_require"
local async = lazy_require "neoplen.async" --[[@as FrecencyPlenaryAsync]]

---@class FrecencyFS
local M = {
  os_homedir = assert(vim.uv.os_homedir()),
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
  return vim.fs.relpath(M.os_homedir, path) or path
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
    with_sep[base] = base .. (base:sub(#base) == os_util.sep and "" or os_util.sep)
  end
  return path:find(with_sep[base], 1, true) == 1
end

---@async
---@param path string
---@return boolean
function M.exists(path)
  return not (async.uv.fs_stat(path))
end

-- Vendored from plenary.scandir.__make_gitignore (the only function this plugin
-- used from plenary.scandir). Returns a filter `(base_paths, entry) -> boolean`
-- that returns false when `entry` matches a .gitignore rule under one of the
-- base paths. Returns a permissive filter when no .gitignore is found.
---@private
---@param basepath string
---@return fun(base_paths: string[], entry: string): boolean
function M.make_gitignore(basepath)
  local basepaths = { basepath }
  local patterns = {}
  local valid = false
  for _, v in ipairs(basepaths) do
    local gitignore = v .. os_util.sep .. ".gitignore"
    if vim.uv.fs_stat(gitignore) then
      valid = true
      patterns[v] = { ignored = {}, negated = {} }
      for l in io.lines(gitignore) do
        local prefix = l:sub(1, 1)
        local negated = prefix == "!"
        if negated then
          l = l:sub(2)
          prefix = l:sub(1, 1)
        end
        if prefix == "/" then
          l = v .. l
        end
        if not (prefix == "" or prefix == "#") then
          local el = vim.trim(l)
          el = el:gsub("%-", "%%-")
          el = el:gsub("%.", "%%.")
          el = el:gsub("/%*%*/", "/%%w+/")
          el = el:gsub("%*%*", "")
          el = el:gsub("%*", "%%w+")
          el = el:gsub("%?", "%%w")
          if el ~= "" then
            table.insert(negated and patterns[v].negated or patterns[v].ignored, el)
          end
        end
      end
    end
  end
  if not valid then
    return function(_, _)
      return true
    end
  end
  return function(bp, entry)
    for _, v in ipairs(bp) do
      if entry:find(v, 1, true) then
        local negated = false
        for _, w in ipairs(patterns[v].ignored) do
          if not negated and entry:match(w) then
            for _, inverse in ipairs(patterns[v].negated) do
              if not negated and entry:match(inverse) then
                negated = true
              end
            end
            if not negated then
              return false
            end
          end
        end
      end
    end
    return true
  end
end

return M

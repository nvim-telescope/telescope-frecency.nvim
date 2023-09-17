local Path = require "plenary.path" --[[@as PlenaryPath]]
local scandir = require "plenary.scandir"
local log = require "plenary.log"
local uv = vim.uv or vim.loop

---@class FrecencyFS
---@field os_homedir string
---@field joinpath fun(...: string): string
---@field private config FrecencyFSConfig
---@field private ignore_regexes string[]
local FS = {}

---@class FrecencyFSConfig
---@field scan_depth integer?
---@field ignore_patterns string[]

---@param config FrecencyFSConfig
---@return FrecencyFS
FS.new = function(config)
  local self = setmetatable(
    { config = vim.tbl_extend("force", { scan_depth = 100 }, config), os_homedir = assert(uv.os_homedir()) },
    { __index = FS }
  )
  ---@param pattern string
  self.ignore_regexes = vim.tbl_map(function(pattern)
    local escaped = pattern:gsub("[%-%.%+%[%]%(%)%$%^%%%?%*]", "%%%1")
    local regex = escaped:gsub("%%%*", ".*"):gsub("%%%?", ".")
    return "^" .. regex .. "$"
  end, self.config.ignore_patterns)
  ---This is needed for Neovim v0.9.0.
  self.joinpath = vim.fs.joinpath or function(...)
    return (table.concat({ ... }, "/"):gsub("//+", "/"))
  end
  return self
end

---@param path string?
---@return boolean
function FS:is_valid_path(path)
  return not not path and Path:new(path):is_file() and not self:is_ignored(path)
end

---@param path string
---@return function
function FS:scan_dir(path)
  log.debug { path = path }
  local gitignore = self:make_gitignore(path)
  return coroutine.wrap(function()
    for name, type in
      vim.fs.dir(path, {
        depth = self.config.scan_depth,
        skip = function(dirname)
          if self:is_ignored(self.joinpath(path, dirname)) then
            return false
          end
        end,
      })
    do
      local fullpath = self.joinpath(path, name)
      if type == "file" and not self:is_ignored(fullpath) and gitignore({ path }, fullpath) then
        coroutine.yield(name)
      end
    end
  end)
end

---@param path string
---@return string
function FS:relative_from_home(path)
  return Path:new(path):make_relative(self.os_homedir)
end

---@private
---@param path string
---@return boolean
function FS:is_ignored(path)
  for _, regex in ipairs(self.ignore_regexes) do
    if path:find(regex) then
      return true
    end
  end
  return false
end

---@private
---@param basepath string
---@return fun(base_paths: string[], entry: string): boolean
function FS:make_gitignore(basepath)
  return scandir.__make_gitignore { basepath } or function(_, _)
    return true
  end
end

return FS

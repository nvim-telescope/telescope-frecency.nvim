local Path = require "plenary.path" --[[@as PlenaryPath]]
local scandir = require "plenary.scandir"
local log = require "frecency.log"

---@class FrecencyFS
---@field private ignore_regexes string[]
local FS = {}

---@class FrecencyFSConfig
---@field ignore_patterns string[]

---@param config FrecencyFSConfig
---@return FrecencyFS
FS.new = function(config)
  local self = setmetatable({ config = config }, { __index = FS })
  ---@param pattern string
  self.ignore_regexes = vim.tbl_map(function(pattern)
    local escaped = pattern:gsub("[%-%.%+%[%]%(%)%$%^%%%?%*]", "%%%1")
    local regex = escaped:gsub("%%%*", ".*"):gsub("%%%?", ".")
    return "^" .. regex .. "$"
  end, self.config.ignore_patterns)
  return self
end

---@param path string
---@return boolean
function FS:is_valid_path(path)
  return Path:new(path):is_file() and not self:is_ignored(path)
end

---@param path string
function FS:scan_dir(path)
  log:debug("%s", { path = path })
  local gitignore = self:make_gitignore(path)
  return coroutine.wrap(function()
    for name, type in
      vim.fs.dir(path, {
        depth = 100,
        skip = function(dirname)
          if self:is_ignored(vim.fs.joinpath(path, dirname)) then
            return false
          end
        end,
      })
    do
      local fullpath = vim.fs.joinpath(path, name)
      if type == "file" and not self:is_ignored(fullpath) and gitignore({ path }, fullpath) then
        coroutine.yield(name)
      end
    end
  end)
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

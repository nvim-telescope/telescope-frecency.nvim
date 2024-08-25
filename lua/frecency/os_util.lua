local lazy_require = require "frecency.lazy_require"
local Path = lazy_require "plenary.path" --[[@as FrecencyPlenaryPath]]
local uv = vim.uv or vim.loop

---@class FrecencyOSUtil
local M = {
  is_windows = uv.os_uname().sysname == "Windows_NT",
}

---@type fun(filename: string): string
M.normalize_sep = M.is_windows
    and function(filename)
      if not filename:find("/", 1, true) or filename:match "^%a+://" then
        return filename
      end
      local replaced = filename:gsub("/", Path.path.sep)
      return replaced
    end
  or function(filename)
    return filename
  end

--- Join path segments into a single path string.
--- NOTE: Do not use vim.fs.joinpath because it does not work on Windows.
---@type fun(...: string): string
M.join_path = M.is_windows and function(...)
  return M.normalize_sep(Path:new(...).filename)
end or function(...)
  return Path:new(...).filename
end

return M

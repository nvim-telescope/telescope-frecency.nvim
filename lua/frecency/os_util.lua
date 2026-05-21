---@class FrecencyOSUtil
local M = {
  is_windows = vim.uv.os_uname().sysname == "Windows_NT",
}

M.sep = M.is_windows and "\\" or "/"

---@type fun(filename: string): string
M.normalize_sep = M.is_windows
    and function(filename)
      if not filename:find("/", 1, true) or filename:match "^%a+://" then
        return filename
      end
      local replaced = filename:gsub("/", "\\")
      return replaced
    end
  or function(filename)
    return filename
  end

-- vim.fs.joinpath always uses "/", so on Windows we normalize separators to "\"
-- to keep paths consistent with the rest of the codebase (which compares paths
-- with starts_with and stores them in the on-disk database).
---@type fun(...: string): string
M.join_path = M.is_windows and function(...)
  return M.normalize_sep(vim.fs.joinpath(...))
end or function(...)
  return vim.fs.joinpath(...)
end

return M

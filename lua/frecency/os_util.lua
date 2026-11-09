---@class FrecencyOSUtil
local M = {
  is_windows = vim.uv.os_uname().sysname == "Windows_NT",
}

-- Paths use "/" as the separator on all platforms, the same as telescope.nvim.
M.sep = "/"

---Converts "\" to "/" on Windows. URIs and paths on other platforms are
---returned as is.
---@type fun(path: string): string
M.normalize = M.is_windows
    and function(path)
      if not path:find("\\", 1, true) or path:match "^%a+://" then
        return path
      end
      local replaced = path:gsub("\\", "/")
      return replaced
    end
  or function(path)
    return path
  end

---@param ... string
---@return string
function M.join_path(...)
  return M.normalize(vim.fs.joinpath(...))
end

return M

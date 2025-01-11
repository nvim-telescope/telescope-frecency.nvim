---@class FrecencyWebDevicons
local M = {
  ---@param name string?
  ---@param ext string?
  ---@param opts table?
  ---@return string
  ---@return string
  get_icon = function(name, ext, opts)
    local ok, web_devicons = pcall(require, "nvim-web-devicons")
    if not ok then
      return "", ""
    end
    return web_devicons.get_icon(name, ext, opts)
  end,
}

return M

local config = require "frecency.config"

---@class WebDeviconsModule
---@field get_icon fun(name?: string, ext?: string, opts?: table): string, string

---@class WebDevicons
---@field is_enabled boolean
---@field private web_devicons WebDeviconsModule
local WebDevicons = {}

---@return WebDevicons
WebDevicons.new = function()
  local ok, web_devicons = pcall(require, "nvim-web-devicons")
  return setmetatable(
    { is_enabled = not config.disable_devicons and ok, web_devicons = web_devicons },
    { __index = WebDevicons }
  )
end

---@param name string?
---@param ext string?
---@param opts table?
---@return string
---@return string
function WebDevicons:get_icon(name, ext, opts)
  if self.is_enabled then
    return self.web_devicons.get_icon(name, ext, opts)
  end
  return "", ""
end

return WebDevicons

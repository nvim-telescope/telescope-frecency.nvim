local WebDevicons = {}

local ok, web_devicons = pcall(require, "nvim-web-devicons")

function WebDevicons.is_enabled()
  return ok
end

---@param name string?
---@param ext string?
---@param opts table?
---@return string
---@return string
function WebDevicons.get_icon(name, ext, opts)
  if ok then
    return web_devicons.get_icon(name, ext, opts)
  end
  return "", ""
end

return WebDevicons

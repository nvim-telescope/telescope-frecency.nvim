return {
  ---@param name string?
  ---@param ext string?
  ---@param opts table?
  ---@return string
  ---@return string
  get_icon = function(name, ext, opts)
    local ok, web_devicons = pcall(require, "nvim-web-devicons")
    return ok and web_devicons.get_icon(name, ext, opts) or "", ""
  end,
}

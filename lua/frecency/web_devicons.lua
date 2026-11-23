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

  ---Returns the extension to look up the icon with. It keeps the last two parts
  ---of the name when it has two or more dots, such as `test.js` for `foo.test.js`.
  ---This is the same as `file_extension()` in telescope.utils, which is no
  ---longer exposed.
  ---@param filename string
  ---@return string
  file_extension = function(filename)
    local parts = vim.split(filename, ".", { plain = true })
    return table.concat(vim.list_slice(parts, #parts > 2 and #parts - 1 or #parts), ".")
  end,
}

return M

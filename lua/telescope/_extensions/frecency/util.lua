local uv  = vim.loop

local util = {}

util.string_isempty = function(s)
  return s == nil or s == ''
end

util.string_starts = function(str, start)
  return string.sub(str, 1, str.len(start)) == start
end

util.split = function(s, delimiter)
  local result = {}
  for match in (s .. delimiter):gmatch("(.-)" .. delimiter) do
    table.insert(result, match)
  end
  return result
end

util.fs_stat = function(path)  -- TODO: move this to new file with M
  local stat = uv.fs_stat(path)
  local res  = {}
  res.exists      = stat and true or false -- TODO: this is silly
  res.isdirectory = (stat and stat.type == "directory") and true or false

  return res
end

return util

local uv  = vim.loop

local util = {}

-- stolen from penlight

-- escape any Lua 'magic' characters in a string
util.escape = function(str)
  return (str:gsub('[%-%.%+%[%]%(%)%$%^%%%?%*]','%%%1'))
end

util.filemask = function(mask)
  mask = util.escape(mask)
  return '^'..mask:gsub('%%%*','.*'):gsub('%%%?','.')..'$'
end

util.filename_match = function(filename, pattern)
  return filename:find(util.filemask(pattern)) ~= nil
end

--

util.string_isempty = function(str)
  return str == nil or str == ''
end

util.string_starts = function(str, token)
  return str:sub(1, str:len(token)) == token
end

util.string_ends = function(str, token)
  return str:sub(str:len() - token:len() + 1, -1) == token
end

util.split = function(str, delimiter)
  local result = {}
  for match in str:gmatch("[^" .. delimiter .. "]+") do
    table.insert(result, match)
  end
  return result
end

util.fs_stat = function(path)
  local stat = uv.fs_stat(path)
  local res  = {}
  res.exists      = stat and true or false -- TODO: this is silly
  res.isdirectory = (stat and stat.type == "directory") and true or false

  return res
end

return util

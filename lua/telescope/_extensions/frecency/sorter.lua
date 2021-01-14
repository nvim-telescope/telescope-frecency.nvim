local sorters = require "telescope.sorters"

local my_sorters = {}

local function split(s, delimiter)
  local result = {}
  for match in (s .. delimiter):gmatch("(.-)" .. delimiter) do
    table.insert(result, match)
  end
  return result
end

local substr_highlighter = function(_, prompt, display)
  local highlights = {}
  display = display:lower()

  local search_terms = split(prompt, " ")
  local hl_start, hl_end

  for _, word in pairs(search_terms) do
    hl_start, hl_end = display:find(word, 1, true)
    if hl_start then
      table.insert(highlights, {start = hl_start, finish = hl_end})
    end
  end

  return highlights
end

my_sorters.get_substr_matcher = function(opts)
  opts = opts or {}

  local substr = sorters:new()
  substr.highlighter = substr_highlighter
  substr.scoring_function = function(_, prompt, _, entry)
    local display = entry.name:lower()

    local search_terms = split(prompt, " ")
    local matched
    for _, word in pairs(search_terms) do
       matched = display:find(word, 1, true) and 1 or -1
       if matched == -1 then goto continue end
    end

    ::continue::

    if matched == -1 then
      return -1
    else
      return entry.index
    end
  end

  return substr
end

return my_sorters

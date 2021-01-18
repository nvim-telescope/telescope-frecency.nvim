local sorters = require "telescope.sorters"
local util    = require("telescope._extensions.frecency.util")

local my_sorters = {}

local substr_highlighter = function(_, prompt, display)
  local highlights = {}
  display = display:lower()

  local search_terms = util.split(prompt, "%s")
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
    local display = entry.ordinal:lower()

    local search_terms = util.split(prompt, "%s")
    local matched = 0
    local total_search_terms = 0
    for _, word in pairs(search_terms) do
      total_search_terms = total_search_terms + 1
      if display:find(word, 1, true) then
        matched = matched + 1
      end
    end

    return matched == total_search_terms and entry.index or -1
  end

  return substr
end

return my_sorters

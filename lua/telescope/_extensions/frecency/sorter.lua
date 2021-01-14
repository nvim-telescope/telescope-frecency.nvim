local sorters = require "telescope.sorters"

local my_sorters = {}


local substr_highlighter = function(_, prompt, display)
  local highlights = {}
  display = display:lower()

  local hl_start, hl_end
  hl_start, hl_end = display:find(prompt, 1, true)
  if hl_start then
    table.insert(highlights, {start = hl_start, finish = hl_end})
  end

  return highlights
end

my_sorters.get_substr_matcher = function(opts)
  opts = opts or {}

  local substr = sorters:new()
  substr.highlighter = substr_highlighter
  substr.scoring_function = function(_, prompt, _, entry)
    -- local base_score = frecency:score(prompt, entry)
    local base_score

    -- TODO: split the prompt into components
    base_score = entry.name:find(prompt, 1, true) and 1 or -1

    if base_score == -1 then
      return -1
    end

    if base_score == 0 then
      return entry.index
    else
      return entry.index
    end
  end

  return substr
end

return my_sorters

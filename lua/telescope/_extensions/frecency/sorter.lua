local sorters = require "telescope.sorters"

local my_sorters = {}

my_sorters.get_frecency_sorter = function(opts)
  opts = opts or {}
  opts.ngram_len = 2

  local fuzzy_sorter = sorters.get_generic_fuzzy_sorter(opts)

  local frecency = sorters:new()
  frecency.highlighter = fuzzy_sorter.highlighter
  frecency.scoring_function = function(_, prompt, _, entry)
    local base_score = fuzzy_sorter:score(prompt, entry)

    if base_score == -1 then
      return -1
    end

    if base_score == 0 then
      return entry.index
    else
      return math.min(math.pow(entry.index, 0.25), 2) * base_score
    end
  end

  return frecency
end

return my_sorters

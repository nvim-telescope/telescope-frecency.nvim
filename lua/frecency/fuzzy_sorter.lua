local sorters = require "telescope.sorters"

---@param opts any options for get_fzy_sorter()
return function(opts)
  local fzy_sorter = sorters.get_fzy_sorter(opts)

  return sorters.Sorter:new {
    ---@param prompt string
    ---@param entry FrecencyEntry
    ---@return number
    scoring_function = function(_, prompt, _, entry)
      if #prompt == 0 then
        return 1
      end
      local fzy_score = fzy_sorter:scoring_function(prompt, entry.ordinal)
      if fzy_score <= 0 then
        return -1
      end
      entry.fuzzy_score = (10 / (entry.score == 0 and 1 or entry.score)) - 1 / fzy_score
      return entry.fuzzy_score
    end,

    highlighter = fzy_sorter.highlighter,
  }
end

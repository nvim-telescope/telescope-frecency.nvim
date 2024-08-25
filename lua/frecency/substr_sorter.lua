-- TODO: use this module until telescope's release include this below.
-- https://github.com/nvim-telescope/telescope.nvim/pull/2950

local lazy_require = require "frecency.lazy_require"
local sorters = lazy_require "telescope.sorters"
local util = lazy_require "telescope.utils"

local substr_highlighter = function(make_display)
  return function(_, prompt, display)
    local highlights = {}
    display = make_display(prompt, display)

    local search_terms = util.max_split(prompt, "%s")
    local hl_start, hl_end

    for _, word in pairs(search_terms) do
      hl_start, hl_end = display:find(word, 1, true)
      if hl_start then
        table.insert(highlights, { start = hl_start, finish = hl_end })
      end
    end

    return highlights
  end
end

return function()
  local make_display = vim.o.smartcase
      and function(prompt, display)
        local has_upper_case = not not prompt:match "%u"
        return has_upper_case and display or display:lower()
      end
    or function(_, display)
      return display:lower()
    end

  return sorters.Sorter:new {
    highlighter = substr_highlighter(make_display),
    scoring_function = function(_, prompt, _, entry)
      if #prompt == 0 then
        return 1
      end

      local display = make_display(prompt, entry.ordinal)

      local search_terms = util.max_split(prompt, "%s")
      for _, word in pairs(search_terms) do
        if not display:find(word, 1, true) then
          return -1
        end
      end

      return entry.index
    end,
  }
end

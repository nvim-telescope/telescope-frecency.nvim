-- TODO: use this module until telescope's release include this below.
-- https://github.com/nvim-telescope/telescope.nvim/pull/2950

local lazy_require = require "frecency.lazy_require"
local sorters = lazy_require "telescope.sorters"

return function()
  local change_cases = vim.o.smartcase
      and function(prompt, display)
        local has_upper_case = not not prompt:match "%u"
        return has_upper_case and display or display:lower()
      end
    or function(_, display)
      return display:lower()
    end

  return sorters.Sorter:new {
    highlighter = function(_, prompt, display)
      local text = change_cases(prompt, display)
      local search_terms = vim.split(prompt, "%s+", { trimempty = true })
      return vim
        .iter(search_terms)
        :map(function(word)
          return text:find(word, 1, true)
        end)
        :map(function(start, finish)
          return { start = start, finish = finish }
        end)
        :totable()
    end,

    scoring_function = function(_, prompt, _, entry)
      if #prompt == 0 then
        return 1
      end
      local text = change_cases(prompt, entry.ordinal)
      local search_terms = vim.split(prompt, "%s+", { trimempty = true })
      return vim.iter(search_terms):any(function(word)
        return not text:find(word, 1, true)
      end) and -1 or entry.index
    end,
  }
end

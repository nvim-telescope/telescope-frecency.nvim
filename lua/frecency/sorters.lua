local sorters = require "telescope.sorters"
local util = require "telescope.utils"

local M = {}

---@param prompt string
---@return boolean
local function has_upper_case(prompt)
  return not not prompt:match "%u"
end

---@param prompt string
---@param display string
---@return { start: integer, finish: integer }[]
local function highlighter(_, prompt, display)
  ---@type { start: integer, finish: integer }[]
  local highlights = {}
  display = has_upper_case(prompt) and display or display:lower()

  local search_terms = util.max_split(prompt, "%s")
  local hl_start, hl_end

  for _, word in ipairs(search_terms) do
    hl_start, hl_end = display:find(word, 1, true)
    if hl_start then
      table.insert(highlights, { start = hl_start, finish = hl_end })
    end
  end

  return highlights
end

---@param prompt string
---@param entry FrecencyEntry
---@return integer
local function scoring_function(_, prompt, _, entry)
  if #prompt == 0 then
    return 1
  end

  local display = has_upper_case(prompt) and entry.ordinal or entry.ordinal:lower()

  local search_terms = util.max_split(prompt, "%s")
  for _, word in ipairs(search_terms) do
    if not display:find(word, 1, true) then
      return -1
    end
  end
  return entry.index
end

---This is a sorter similar to telescope.sorters.get_substr_matcher. telescope's
---one always ignore cases, but this sorter deal with them like 'smartcase' way.
function M.get_frecency_matcher()
  return vim.o.smartcase
      and sorters.Sorter:new {
        highlighter = highlighter,
        scoring_function = scoring_function,
      }
    or sorters.get_substr_matcher()
end

return M

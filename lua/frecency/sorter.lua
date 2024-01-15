local sorters = require "telescope.sorters"

---@type table<string, string[]>
local regexp_cache = {}

---@param prompt string
local function regexps(prompt)
  if not regexp_cache[prompt] then
    ---@type string[]
    local res = {}
    for c in prompt:lower():gmatch "." do
      local escaped = c:gsub([=[[%^%$%(%)%%%.%[%]%*%+%-%?]]=], "%%%0")
      table.insert(res, escaped)
    end
    regexp_cache[prompt] = res
  end
  return regexp_cache[prompt]
end

return sorters.Sorter:new {
  ---@param prompt string
  ---@param display string
  highlighter = function(_, prompt, display)
    local converted = display:lower()
    local res = regexps(prompt)
    ---@type { start: number, finish: number }[]
    local highlights = {}
    local init = 1
    for _, re in ipairs(res) do
      local start, finish = converted:find(re, init)
      if start and finish then
        init = finish + 1
        table.insert(highlights, { start = start, finish = finish })
      end
    end
    return highlights
  end,

  ---@param prompt string
  ---@param entry FrecencyEntry
  scoring_function = function(_, prompt, _, entry)
    if #prompt == 0 then
      return 1
    end
    local res = regexps(prompt)
    local display = entry.ordinal:lower()
    return display:match(table.concat(res, ".*")) and entry.index or -1
  end,
}

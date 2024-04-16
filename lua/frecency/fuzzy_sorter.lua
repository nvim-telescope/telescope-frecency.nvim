local config = require "frecency.config"
local sorters = require "telescope.sorters"
local Path = require "plenary.path"

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

---@type table<string, string>
local target_cache = {}
local basename_re = ("[^%s]*$"):format(Path.path.sep)

---@param filename string
---@return string
local function target(filename)
  if not target_cache[filename] then
    target_cache[filename] = config.matcher == "fuzzy" and filename:match(basename_re) or filename
  end
  return target_cache[filename]
end

return sorters.Sorter:new {
  ---@param prompt string
  ---@param display string
  highlighter = function(_, prompt, display)
    local converted = target(display):lower()
    local offset = #display - #converted
    local res = regexps(prompt)
    ---@type { start: number, finish: number }[]
    local highlights = {}
    local init = 1
    for _, re in ipairs(res) do
      local start, finish = converted:find(re, init)
      if start and finish then
        init = finish + 1
        table.insert(highlights, { start = start + offset, finish = finish + offset })
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
    local display = target(entry.ordinal):lower()
    return display:match(table.concat(res, ".*")) and entry.index or -1
  end,
}

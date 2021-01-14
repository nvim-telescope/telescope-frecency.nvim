local sqlwrap   = require("telescope._extensions.frecency.sql_wrapper")

local MAX_TIMESTAMPS = 10

-- modifier used as a weight in the recency_score calculation:
local recency_modifier = {
  [1] = { age = 240   , value = 100 }, -- past 4 hours
  [2] = { age = 1440  , value = 80  }, -- past day
  [3] = { age = 4320  , value = 60  }, -- past 3 days
  [4] = { age = 10080 , value = 40  }, -- past week
  [5] = { age = 43200 , value = 20  }, -- past month
  [6] = { age = 129600, value = 10  }  -- past 90 days
}

local sql_wrapper = nil

local function init()
  if sql_wrapper then return end

  sql_wrapper = sqlwrap:new()
  sql_wrapper:bootstrap()

  -- setup autocommands
  vim.api.nvim_command("augroup TelescopeFrecency")
  vim.api.nvim_command("autocmd!")
  vim.api.nvim_command("autocmd BufEnter * lua require'telescope._extensions.frecency.db_client'.autocmd_handler(vim.fn.expand('<amatch>'))")
  vim.api.nvim_command("augroup END")
end

-- TODO: move these to util.lua
local function string_isempty(s)
  return s == nil or s == ''
end

local function calculate_file_score(frequency, timestamps)
  local recency_score = 0
  for _, ts in pairs(timestamps) do
    for _, rank in ipairs(recency_modifier) do
      if ts.age <= rank.age then
        recency_score = recency_score + rank.value
        goto continue
      end
    end
    ::continue::
  end

  return frequency * recency_score / MAX_TIMESTAMPS
end

local function filter_timestamps(timestamps, file_id)
  local res = {}
  for _, entry in pairs(timestamps) do
    if entry.file_id == file_id then
      table.insert(res, entry)
    end
  end
  return res
end

local function get_file_scores()
  if not sql_wrapper then return end

  local files           = sql_wrapper:do_transaction('get_all_filepaths')
  local timestamp_ages  = sql_wrapper:do_transaction('get_all_timestamp_ages')

  local scores = {}
  for _, file_entry in ipairs(files) do
    table.insert(scores, {
      filename = file_entry.path,
      score    = calculate_file_score(file_entry.count, filter_timestamps(timestamp_ages, file_entry.id))
    })
  end

  -- sort the table
  local function compare(a, b)
    return a.score > b.score
  end
  table.sort(scores, compare)

  return scores
end

local function autocmd_handler(filepath)
  if not sql_wrapper or string_isempty(filepath) then return end

  -- check if file is registered as loaded
  if not vim.b.frecency_registered then
    vim.b.frecency_registered = 1
    sql_wrapper:update(filepath)
  end
end

return {
  init            = init,
  get_file_scores = get_file_scores,
  autocmd_handler = autocmd_handler,
}

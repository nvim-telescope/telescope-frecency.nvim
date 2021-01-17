local sqlwrap = require("telescope._extensions.frecency.sql_wrapper")
local util    = require("telescope._extensions.frecency.util")

local MAX_TIMESTAMPS = 10
local DB_REMOVE_SAFETY_THRESHOLD = 10

-- modifier used as a weight in the recency_score calculation:
local recency_modifier = {
  [1] = { age = 240   , value = 100 }, -- past 4 hours
  [2] = { age = 1440  , value = 80  }, -- past day
  [3] = { age = 4320  , value = 60  }, -- past 3 days
  [4] = { age = 10080 , value = 40  }, -- past week
  [5] = { age = 43200 , value = 20  }, -- past month
  [6] = { age = 129600, value = 10  }  -- past 90 days
}

local default_ignore_patterns = {
  "*.git/*", "*/tmp/*"
}

local sql_wrapper = nil

local function import_oldfiles()
  local oldfiles = vim.api.nvim_get_vvar("oldfiles")
  for _, filepath in pairs(oldfiles) do
    sql_wrapper:update(filepath)
  end
  print(("Telescope-Frecency: Imported %d entries from oldfiles."):format(#oldfiles))
end

local function file_is_ignored(filepath)
  local is_ignored = false
  for _, ignore_pattern in pairs(default_ignore_patterns) do
    if util.filename_match(filepath, ignore_pattern) then
      is_ignored = true
      goto continue
    end
  end

  ::continue::
  return is_ignored
end

local function validate()
  if not sql_wrapper then return {} end

  local queries = sql_wrapper.queries
  local files = sql_wrapper:do_transaction(queries.file_get_entries, {})
  local pending_remove = {}
  for _, entry in pairs(files) do
    if not util.fs_stat(entry.path).exists -- file no longer exists
      or file_is_ignored(entry.path) then -- cleanup entries that match the _current_ ignore list
      table.insert(pending_remove, entry)
    end
  end

   -- don't allow removal of >N values from DB without confirmation
  local confirmed = false
  if #pending_remove > DB_REMOVE_SAFETY_THRESHOLD then
    if vim.fn.confirm("Telescope-Frecency: remove " .. #pending_remove .. " entries from SQLite3 database?", "&Yes\n&No", 2) then
    confirmed = true
    end
  else
    confirmed = true
  end

  if confirmed then
    for _, entry in pairs(pending_remove) do
      -- remove entries from file and timestamp tables
      print("removing entry: " .. entry.path .. "[" .. entry.id .."]")
      sql_wrapper:do_transaction(queries.file_delete_entry , {where = {id = entry.id }})
      sql_wrapper:do_transaction(queries.timestamp_delete_entry, {where = {file_id = entry.id}})
    end
  else
    print("TelescopeFrecency: validation aborted.")
  end
end

local function init()
  if sql_wrapper then return end

  sql_wrapper = sqlwrap:new()
  local first_run = sql_wrapper:bootstrap()
  validate()

  if first_run then
    -- TODO: this needs to be scheduled for after shada load
    vim.defer_fn(import_oldfiles, 100)
  end

  -- setup autocommands
  vim.api.nvim_command("augroup TelescopeFrecency")
  vim.api.nvim_command("autocmd!")
  vim.api.nvim_command("autocmd BufWinEnter,BufWritePost * lua require'telescope._extensions.frecency.db_client'.autocmd_handler(vim.fn.expand('<amatch>'))")
  vim.api.nvim_command("augroup END")
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

local function filter_workspace(filelist, workspace_path)
  local res = {}
  for _, entry in pairs(filelist) do
    if util.string_starts(entry.path, workspace_path) then
      table.insert(res, entry)
    end
  end
  return res
end

local function get_file_scores(opts)
  if not sql_wrapper then return {} end

  local queries = sql_wrapper.queries
  local scores = {}
  local files           = sql_wrapper:do_transaction(queries.file_get_entries, {})
  local timestamp_ages  = sql_wrapper:do_transaction(queries.timestamp_get_all_entry_ages, {})

  if vim.tbl_isempty(files) then return scores end

  -- filter to LSP workspace directory
  local buf_workspaces = opts.lsp_workspace_filter and vim.lsp.buf.list_workspace_folders() or {}
  if not vim.tbl_isempty(buf_workspaces) then
    for _, ws_path in pairs(buf_workspaces) do
      files = filter_workspace(files, ws_path)
    end
  end

  for _, file_entry in ipairs(files) do
    table.insert(scores, {
      filename = file_entry.path,
      score    = calculate_file_score(file_entry.count, filter_timestamps(timestamp_ages, file_entry.id))
    })
  end

  -- sort the table
  table.sort(scores, function(a, b) return a.score > b.score end)

  return scores
end

local function autocmd_handler(filepath)
  if not sql_wrapper or util.string_isempty(filepath) then return end

  -- check if file is registered as loaded
  if not vim.b.telescope_frecency_registered then
    -- allow [noname] files to go unregistered until BufWritePost
    if not util.fs_stat(filepath).exists then return end

    if file_is_ignored(filepath) then return end

    vim.b.telescope_frecency_registered = 1
    sql_wrapper:update(filepath)
  end
end

return {
  init            = init,
  get_file_scores = get_file_scores,
  autocmd_handler = autocmd_handler,
}

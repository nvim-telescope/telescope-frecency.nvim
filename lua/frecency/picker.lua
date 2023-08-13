local State = require "frecency.state"
local log = require "plenary.log"
local Path = require "plenary.path" --[[@as PlenaryPath]]
local actions = require "telescope.actions"
local config_values = require("telescope.config").values
local pickers = require "telescope.pickers"
local sorters = require "telescope.sorters"
local utils = require "telescope.utils" --[[@as TelescopeUtils]]
local uv = vim.loop or vim.uv

---@class FrecencyPicker
---@field private config FrecencyPickerConfig
---@field private database FrecencyDatabase
---@field private finder FrecencyFinder
---@field private fs FrecencyFS
---@field private lsp_workspaces string[]
---@field private recency FrecencyRecency
---@field private results table[]
---@field private workspace string?
---@field private workspace_tag_regex string
local Picker = {}

---@class FrecencyPickerConfig
---@field default_workspace_tag string?
---@field editing_bufnr integer
---@field filter_delimiter string
---@field initial_workspace_tag string?
---@field show_unindexed boolean
---@field workspaces table<string, string>

---@class FrecencyPickerEntry
---@field display fun(entry: FrecencyPickerEntry): string
---@field filename string
---@field name string
---@field ordinal string
---@field score number

---@param database FrecencyDatabase
---@param finder FrecencyFinder
---@param fs FrecencyFS
---@param recency FrecencyRecency
---@param config FrecencyPickerConfig
---@return FrecencyPicker
Picker.new = function(database, finder, fs, recency, config)
  local self = setmetatable({
    config = config,
    database = database,
    finder = finder,
    fs = fs,
    lsp_workspaces = {},
    recency = recency,
    results = {},
  }, { __index = Picker })
  local d = self.config.filter_delimiter
  self.workspace_tag_regex = "^%s*(" .. d .. "(%S+)" .. d .. ")"
  return self
end

---@class FrecencyPickerOptions
---@field cwd string
---@field path_display
---| "hidden"
---| "tail"
---| "absolute"
---| "smart"
---| "shorten"
---| "truncate"
---| fun(opts: FrecencyPickerOptions, path: string): string
---@field workspace string?

---@param opts FrecencyPickerOptions?
function Picker:start(opts)
  opts = vim.tbl_extend("force", {
    cwd = uv.cwd(),
    path_display = function(picker_opts, path)
      return self:default_path_display(picker_opts, path)
    end,
  }, opts or {}) --[[@as FrecencyPickerOptions]]
  self.workspace = self:get_workspace(opts.cwd, self.config.initial_workspace_tag)
  log.debug { workspace = self.workspace }
  self.results = self:fetch_results(self.workspace)

  local state = State.new()

  local filepath_formatter = self:filepath_formatter(opts)
  local finder = self.finder:start(state, filepath_formatter, self.results, {
    need_scandir = self.workspace and self.config.show_unindexed and true or false,
    workspace = self.workspace,
    workspace_tag = self.config.initial_workspace_tag,
  })

  local picker = pickers.new(opts, {
    prompt_title = "Frecency",
    finder = finder,
    previewer = config_values.file_previewer(opts),
    sorter = sorters.get_substr_matcher(),
    on_input_filter_cb = self:on_input_filter_cb(state, opts),
    attach_mappings = function(prompt_bufnr)
      return self:attach_mappings(prompt_bufnr)
    end,
  })
  state:set(picker)
  picker:find()
  self:set_prompt_options(picker.prompt_bufnr)
end

function Picker:discard_results()
  -- TODO: implement here when it needs to cache.
end

--- See :h 'complete-functions'
---@param findstart 1|0
---@param base string
---@return integer|string[]|''
function Picker:complete(findstart, base)
  if findstart == 1 then
    local delimiter = self.config.filter_delimiter
    local line = vim.api.nvim_get_current_line()
    local start = line:find(delimiter)
    -- don't complete if there's already a completed `:tag:` in line
    if not start or line:find(delimiter, start + 1) then
      return -3
    end
    return start
  elseif vim.fn.pumvisible() == 1 and #vim.v.completed_item > 0 then
    return ""
  end
  ---@param v string
  local matches = vim.tbl_filter(function(v)
    return vim.startswith(v, base)
  end, self:workspace_tags())
  return #matches > 0 and matches or ""
end

---@private
---@return string[]
function Picker:workspace_tags()
  local tags = vim.tbl_keys(self.config.workspaces)
  table.insert(tags, "CWD")
  if self:get_lsp_workspace() then
    table.insert(tags, "LSP")
  end
  return tags
end

---@private
---@param opts FrecencyPickerOptions
---@param path string
---@return string
function Picker:default_path_display(opts, path)
  local filename = Path:new(path):make_relative(opts.cwd)
  if not self.workspace then
    if vim.startswith(filename, self.fs.os_homedir) then
      filename = "~/" .. self.fs:relative_from_home(filename)
    elseif filename ~= path then
      filename = "./" .. filename
    end
  end
  return filename
end

---@private
---@param cwd string
---@param tag string?
---@return string?
function Picker:get_workspace(cwd, tag)
  tag = tag or self.config.default_workspace_tag
  if not tag then
    return nil
  elseif self.config.workspaces[tag] then
    return self.config.workspaces[tag]
  elseif tag == "LSP" then
    return self:get_lsp_workspace()
  elseif tag == "CWD" then
    return cwd
  end
end

---@private
---@param workspace string?
---@param datetime string? ISO8601 format string
---@return FrecencyFile[]
function Picker:fetch_results(workspace, datetime)
  log.debug { workspace = workspace or "NONE" }
  local start_files = os.clock()
  local files = self.database:get_files(workspace)
  log.debug { files = #files }
  log.debug(("it takes %f seconds in fetching files with workspace: %s"):format(os.clock() - start_files, workspace))
  local start_timesatmps = os.clock()
  local timestamps = self.database:get_timestamps(datetime)
  log.debug { timestamps = #timestamps }
  log.debug(("it takes %f seconds in fetching all timestamps"):format(os.clock() - start_timesatmps))
  local start_results = os.clock()
  local elapsed_recency = 0
  ---@type table<integer,number[]>
  local age_map = {}
  for _, timestamp in ipairs(timestamps) do
    if not age_map[timestamp.file_id] then
      age_map[timestamp.file_id] = {}
    end
    table.insert(age_map[timestamp.file_id], timestamp.age)
  end
  for _, file in ipairs(files) do
    local start_recency = os.clock()
    local ages = age_map[file.id] --[[@as number[]?]]
    file.score = ages and self.recency:calculate(file.count, ages) or 0
    elapsed_recency = elapsed_recency + (os.clock() - start_recency)
  end
  log.debug(("it takes %f seconds in calculating recency"):format(elapsed_recency))
  log.debug(("it takes %f seconds in making results"):format(os.clock() - start_results))

  local start_sort = os.clock()
  table.sort(files, function(a, b)
    return a.score > b.score
  end)
  log.debug(("it takes %f seconds in sorting"):format(os.clock() - start_sort))
  return files
end

---@private
---@return string?
function Picker:get_lsp_workspace()
  if vim.tbl_isempty(self.lsp_workspaces) then
    self.lsp_workspaces = vim.api.nvim_buf_call(self.config.editing_bufnr, vim.lsp.buf.list_workspace_folders)
  end
  return self.lsp_workspaces[1]
end

---@private
---@param state FrecencyState
---@param picker_opts table
---@return fun(prompt: string): table
function Picker:on_input_filter_cb(state, picker_opts)
  local filepath_formatter = self:filepath_formatter(picker_opts)
  return function(prompt)
    local workspace
    local matched, tag = prompt:match(self.workspace_tag_regex)
    local opts = { prompt = matched and prompt:sub(matched:len() + 1) or prompt }
    if prompt == "" then
      workspace = self:get_workspace(picker_opts.cwd, self.config.initial_workspace_tag)
    else
      workspace = self:get_workspace(picker_opts.cwd, tag) or self.workspace
    end
    if self.workspace ~= workspace then
      self.workspace = workspace
      self.results = self:fetch_results(workspace)
      opts.updated_finder = self.finder:start(state, filepath_formatter, self.results, {
        initial_results = self.results,
        need_scandir = self.workspace and self.config.show_unindexed and true or false,
        workspace = self.workspace,
        workspace_tag = tag,
      })
    end
    return opts
  end
end

---@private
---@param _ integer
---@return boolean
function Picker:attach_mappings(_)
  actions.select_default:replace_if(function()
    return vim.fn.complete_info().pum_visible == 1
  end, function()
    local keys = vim.fn.complete_info().selected == -1 and "<C-e><BS><Right>" or "<C-y><Right>:"
    local accept_completion = vim.api.nvim_replace_termcodes(keys, true, false, true)
    vim.api.nvim_feedkeys(accept_completion, "n", true)
  end)
  return true
end

---@private
---@param bufnr integer
---@return nil
function Picker:set_prompt_options(bufnr)
  vim.bo[bufnr].filetype = "frecency"
  vim.bo[bufnr].completefunc = "v:lua.require'telescope'.extensions.frecency.complete"
  vim.keymap.set("i", "<Tab>", "pumvisible() ? '<C-n>' : '<C-x><C-u>'", { buffer = bufnr, expr = true })
  vim.keymap.set("i", "<S-Tab>", "pumvisible() ? '<C-p>' : ''", { buffer = bufnr, expr = true })
end

---@alias FrecencyFilepathFormatter fun(workspace: string?): fun(filename: string): string): string

---@private
---@param picker_opts table
---@return FrecencyFilepathFormatter
function Picker:filepath_formatter(picker_opts)
  ---@param workspace string?
  return function(workspace)
    local opts = {}
    for k, v in pairs(picker_opts) do
      opts[k] = v
    end
    opts.cwd = workspace or self.fs.os_homedir

    return function(filename)
      return utils.transform_path(opts, filename)
    end
  end
end

return Picker

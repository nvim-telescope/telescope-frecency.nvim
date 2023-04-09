local has_devicons, devicons = pcall(require, "nvim-web-devicons")
local p = require "plenary.path"
local util = require "frecency.util"
local os_home = vim.loop.os_homedir()
local os_path_sep = p.path.sep
local actions = require "telescope.actions"
local conf = require("telescope.config").values
local entry_display = require "telescope.pickers.entry_display"
local finders = require "telescope.finders"
local pickers = require "telescope.pickers"
local sorters = require "telescope.sorters"
local ts_util = require "telescope.utils"
local db = require "frecency.db"

---TODO: Describe FrecencyPicker fields

---@class FrecencyPicker
---@field db FrecencyDB: where the files will be stored
---@field results table
---@field active_filter string
---@field active_filter_tag string
---@field previous_buffer string
---@field cwd string
---@field lsp_workspaces table
---@field picker table
local m = {
  results = {},
  active_filter = nil,
  active_filter_tag = nil,
  last_filter = nil,
  previous_buffer = nil,
  cwd = nil,
  lsp_workspaces = {},
  picker = {},
}

m.__index = m

---@class FrecencyConfig
---@field show_unindexed boolean: default true
---@field show_filter_column boolean: default true
---@field user_workspaces table: default {}
---@field disable_devicons boolean: default false
---@field default_workspace string: default nil
m.config = {
  show_scores = true,
  show_unindexed = true,
  show_filter_column = true,
  user_workspaces = {},
  disable_devicons = false,
  default_workspace = nil,
}

---Setup frecency picker
m.set_buf = function()
  util.buf_set {
    m.picker.prompt_bufnr,
    options = { filetype = "frecency", completefunc = "frecency#FrecencyComplete" },
    mappings = {
      expr = true,
      ["i|<Tab>"] = "pumvisible() ? '<C-n>'  : '<C-x><C-u>'",
      ["i|<S-Tab>"] = "pumvisible() ? '<C-p>'  : ''",
    },
  }
end

---returns `true` if workspaces exit
---@param bufnr integer
---@param force boolean?
---@return boolean workspaces_exist
m.fetch_lsp_workspaces = function(bufnr, force)
  if not vim.tbl_isempty(m.lsp_workspaces) and not force then
    return true
  end

  local lsp_workspaces = vim.api.nvim_buf_call(bufnr, vim.lsp.buf.list_workspace_folders)
  if not vim.tbl_isempty(lsp_workspaces) then
    m.lsp_workspaces = lsp_workspaces
    return true
  end

  m.lsp_workspaces = {}
  return false
end

---Update Frecency Picker result
---@param filter string
---@return boolean
m.update = function(filter)
  local filter_updated = false
  local ws_dir = filter and m.config.user_workspaces[filter] or nil

  if filter == "LSP" and not vim.tbl_isempty(m.lsp_workspaces) then
    ws_dir = m.lsp_workspaces[1]
  elseif filter == "CWD" then
    ws_dir = m.cwd
  end

  if ws_dir ~= m.active_filter then
    filter_updated = true
    m.active_filter, m.active_filter_tag = ws_dir, filter
  end

  m.results = (vim.tbl_isempty(m.results) or filter_updated)
      and db.files.get { ws_dir = ws_dir, show_unindexed = m.config.show_unindexed }
    or m.results

  return filter_updated
end

---@param opts table telescope picker table
---@return fun(filename: string): string
m.filepath_formatter = function(opts)
  local path_opts = {}
  for k, v in pairs(opts) do
    path_opts[k] = v
  end

  return function(filename)
    path_opts.cwd = m.active_filter or m.cwd
    return ts_util.transform_path(path_opts, filename)
  end
end

---Create entry maker function.
---@param entry table
---@return function
m.maker = function(entry)
  local filter_column_width = (function()
    -- TODO: Only add +1 if m.show_filter_thing is true, +1 is for the trailing slash
    if m.active_filter then
      return (m.active_filter_tag == "LSP" or m.active_filter_tag == "CWD")
          and #(ts_util.path_tail(m.active_filter)) + 1
        or #(p:new(m.active_filter):make_relative(os_home)) - 30
    else
      return 0
    end
  end)()

  local displayer = entry_display.create {
    separator = "",
    hl_chars = { [os_path_sep] = "TelescopePathSeparator" },
    items = (function()
      local i = m.config.show_scores and { { width = 8 } } or {}
      if has_devicons and not m.config.disable_devicons then
        table.insert(i, { width = 2 })
      end
      if m.config.show_filter_column then
        table.insert(i, { width = filter_column_width })
      end
      table.insert(i, { remaining = true })
      return i
    end)(),
  }

  local filter_path = (function()
    if m.config.show_filter_column then
      if m.active_filter_tag == "LSP" or m.active_filter_tag == "CWD" then
        return ts_util.path_tail(m.active_filter) .. os_path_sep
      elseif m.active_filter then
        return p:new(m.active_filter):make_relative(os_home) .. os_path_sep
      end
    end
    return nil
  end)()

  local formatter = m.filepath_formatter(m.opts)

  return {
    filename = entry.path,
    ordinal = entry.path,
    name = entry.path,
    score = entry.score,
    display = function(e)
      return displayer((function()
        local i = m.config.show_scores and { { entry.score, "TelescopeFrecencyScores" } } or {}
        if has_devicons and not m.config.disable_devicons then
          table.insert(i, { devicons.get_icon(e.name, string.match(e.name, "%a+$"), { default = true }) })
        end
        if filter_path then
          table.insert(i, { filter_path, "Directory" })
        end
        table.insert(i, {
          formatter(e.name),
          util.buf_is_loaded(e.name) and "TelescopeBufferLoaded" or "",
        })
        return i
      end)())
    end,
  }
end

---Find files
---@param opts table: telescope picker opts
m.fd = function(opts)
  opts = opts or {}

  if not opts.path_display then
    opts.path_display = function(path_opts, filename)
      local original_filename = filename

      filename = p:new(filename):make_relative(path_opts.cwd)
      if not m.active_filter then
        if vim.startswith(filename, os_home) then
          filename = "~/" .. p:new(filename):make_relative(os_home)
        elseif filename ~= original_filename then
          filename = "./" .. filename
        end
      end

      return filename
    end
  end

  m.previous_buffer, m.cwd, m.opts = vim.fn.bufnr "%", vim.fn.expand(opts.cwd or vim.loop.cwd()), opts
  -- TODO: should we update this every time it calls frecency on other buffers?
  m.fetch_lsp_workspaces(m.previous_buffer)
  m.update()

  local picker_opts = {
    prompt_title = "Frecency",
    finder = finders.new_table { results = m.results, entry_maker = m.maker },
    previewer = conf.file_previewer(opts),
    sorter = sorters.get_substr_matcher(opts),
  }

  picker_opts.on_input_filter_cb = function(query_text)
    local o = {}
    local delim = m.config.filter_delimiter or ":" -- check for :filter: in query text
    local matched, new_filter = query_text:match("^%s*(" .. delim .. "(%S+)" .. delim .. ")")
    new_filter = new_filter or opts.workspace or m.config.default_workspace

    o.prompt = matched and query_text:sub(matched:len() + 1) or query_text
    if m.update(new_filter) then
      m.last_filter = new_filter
      o.updated_finder = finders.new_table { results = m.results, entry_maker = m.maker }
    end

    return o
  end

  picker_opts.attach_mappings = function(prompt_bufnr)
    actions.select_default:replace_if(function()
      return vim.fn.complete_info().pum_visible == 1
    end, function()
      local keys = vim.fn.complete_info().selected == -1 and "<C-e><Bs><Right>" or "<C-y><Right>:"
      local accept_completion = vim.api.nvim_replace_termcodes(keys, true, false, true)
      vim.api.nvim_feedkeys(accept_completion, "n", true)
    end)
    return true
  end

  m.picker = pickers.new(opts, picker_opts)
  m.picker:find()
  m.set_buf()
end

---TODO: this seems to be forgotten and just exported in old implementation.
---@return table
m.workspace_tags = function()
  -- Add user config workspaces.
  -- TODO: validate that workspaces are existing directories
  local tags = {}
  for k, _ in pairs(m.config.user_workspaces) do
    table.insert(tags, k)
  end

  -- Add CWD filter
  --  NOTE: hmmm :cwd::lsp: is easier to write.
  table.insert(tags, "CWD")

  -- Add LSP workpace(s)
  if m.fetch_lsp_workspaces(m.previous_buffer, true) then
    table.insert(tags, "LSP")
  end

  -- TODO: sort tags - by collective frecency? (?????? is this still relevant)
  return tags
end

---Setup Frecency Picker
---@param db FrecencyDB
---@param config FrecencyConfig
m.setup = function(config)
  m.config = vim.tbl_extend("keep", config, m.config)
  db.set_config(config)

  --- Seed files table with oldfiles when it's empty.
  if not p:new(db.db.uri):exists() then
    -- TODO: this needs to be scheduled for after shada load??
    local oldfiles = vim.api.nvim_get_vvar "oldfiles"
    for _, path in ipairs(oldfiles) do
      fs.insert { path = path, count = 0 } -- TODO: remove when sql.nvim#97 is closed
    end
    vim.notify(("Telescope-Frecency: Imported %d entries from oldfiles."):format(#oldfiles))
  end

  -- TODO: perhaps ignore buffer without file path here?
  vim.cmd [[
    augroup TelescopeFrecency
      autocmd!
      autocmd BufWinEnter,BufWritePost * lua require'frecency.db'.update()
    augroup END
    ]]
end

return m

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
local log = require "frecency.log"

local m = {
  results = {},
  active_filter = nil,
  active_filter_tag = nil,
  last_filter = nil,
  previous_buffer = nil,
  cwd = nil,
  lsp_workspaces = {},
  picker = {},
  updated = false,
}

m.__index = m

m.config = {
  show_scores = true,
  show_unindexed = true,
  show_filter_column = true,
  workspaces = {},
  disable_devicons = false,
  default_workspace = nil,
}

---Setup frecency picker
m.set_prompt_options = function(buffer)
  vim.bo[buffer].filetype = "frecency"
  vim.bo[buffer].completefunc = "v:lua.require'telescope'.extensions.frecency.complete"
  vim.keymap.set("i", "<Tab>", "pumvisible() ? '<C-n>' : '<C-x><C-u>'", { buffer = buffer, expr = true })
  vim.keymap.set("i", "<S-Tab>", "pumvisible() ? '<C-p>' : ''", { buffer = buffer, expr = true })
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
  local ws_dir = filter and m.config.workspaces[filter] or nil

  if filter == "LSP" and not vim.tbl_isempty(m.lsp_workspaces) then
    ws_dir = m.lsp_workspaces[1]
  elseif filter == "CWD" then
    ws_dir = m.cwd
  end

  if ws_dir ~= m.active_filter then
    filter_updated = true
    m.active_filter, m.active_filter_tag = ws_dir, filter
  end

  m.results = (vim.tbl_isempty(m.results) or m.updated or filter_updated)
      and db.get_files { ws_path = ws_dir, show_unindexed = m.config.show_unindexed }
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

m.should_show_tail = function()
  local filters = type(m.config.show_filter_column) == "table" and m.config.show_filter_column or { "LSP", "CWD" }
  return vim.tbl_contains(filters, m.active_filter_tag)
end

---Create entry maker function.
---@param entry table
---@return function
m.maker = function(entry)
  local filter_column_width = (function()
    if m.active_filter then
      if m.should_show_tail() then
        -- TODO: Only add +1 if m.show_filter_thing is true, +1 is for the trailing slash
        return #(ts_util.path_tail(m.active_filter)) + 1
      end
      return #(p:new(m.active_filter):make_relative(os_home)) + 1
    end
    return 0
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
    if m.config.show_filter_column and m.active_filter then
      return m.should_show_tail() and ts_util.path_tail(m.active_filter) .. os_path_sep
        or p:new(m.active_filter):make_relative(os_home) .. os_path_sep
    end
    return ""
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
        table.insert(i, { filter_path, "Directory" })
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
  m.set_prompt_options(m.picker.prompt_bufnr)
end

---TODO: this seems to be forgotten and just exported in old implementation.
---@return table
m.workspace_tags = function()
  -- Add user config workspaces.
  -- TODO: validate that workspaces are existing directories
  local tags = {}
  for k, _ in pairs(m.config.workspaces) do
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

m.complete = function(findstart, base)
  if findstart == 1 then
    local line = vim.api.nvim_get_current_line()
    local start = line:find ":"
    -- don't complete if there's already a completed `:tag:` in line
    if not start or line:find(":", start + 1) then
      return -3
    end
    return start
  else
    if vim.fn.pumvisible() == 1 and #vim.v.completed_item > 0 then
      return ""
    end

    local matches = vim.tbl_filter(function(v)
      return vim.startswith(v, base)
    end, m.workspace_tags())

    return #matches > 0 and matches or ""
  end
end

---Setup Frecency Picker
---@param db FrecencyDB
---@param config FrecencyConfig
m.setup = function(config)
  m.config = vim.tbl_extend("keep", config, m.config)
  db.set_config(config)

  --- Seed files table with oldfiles when it's empty.
  if db.sqlite.files:count() == 0 then
    -- TODO: this needs to be scheduled for after shada load??
    for _, path in ipairs(vim.v.oldfiles) do
      db.sqlite.files:insert { path = path, count = 0 } -- TODO: remove when sql.nvim#97 is closed
    end
    vim.notify(("Telescope-Frecency: Imported %d entries from oldfiles."):format(#vim.v.oldfiles))
  end

  -- TODO: perhaps ignore buffer without file path here?
  local group = vim.api.nvim_create_augroup("TelescopeFrecency", {})
  vim.api.nvim_create_autocmd({ "BufWinEnter", "BufWritePost" }, {
    group = group,
    callback = function(args)
      local path = vim.api.nvim_buf_get_name(args.buf)
      local has_added_entry = db.update(path)
      m.updated = m.updated or has_added_entry
    end,
  })

  vim.api.nvim_create_user_command("FrecencyValidate", function(cmd_info)
    db.validate { force = cmd_info.bang }
  end, { bang = true, desc = "Clean up DB for telescope-frecency" })

  if db.config.auto_validate then
    db.validate { auto = true }
  end
end

return m

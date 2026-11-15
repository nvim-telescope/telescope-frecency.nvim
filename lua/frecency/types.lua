-- luacheck: no max comment line length
-- luacheck: no unused

---@diagnostic disable: unused-local, missing-return

-- NOTE: types are borrowed from plenary.nvim

---@class FsStatMtime
---@field sec integer
---@field nsec integer

---@class FsStat
---@field mtime FsStatMtime
---@field size integer
---@field type "file"|"directory"

-- NOTE: types are for telescope.nvim

---@alias FrecencyTelescopeEntryDisplayer fun(items: string[]): table

---@class FrecencyTelescopeEntryDisplayOptions
---@field separator? string
---@field hl_chars? table<string, string>
---@field items string[]

---@class FrecencyTelescopeEntryDisplay
---@field create fun(opts: FrecencyTelescopeEntryDisplayOptions): FrecencyTelescopeEntryDisplayer

---@class FrecencyTelescopePathStyleIndex
---@field [1] integer start index of the path
---@field [2] integer finish index of the path

---@class FrecencyTelescopePathStyle
---@field [1] FrecencyTelescopePathStyleIndex
---@field [2] string highlight name

---@class FrecencyTelescopeUtils
---@field path_tail fun(path: string): string
---@field transform_path fun(opts: table, path: string): string, FrecencyTelescopePathStyle[]
---@field buf_is_loaded fun(filename: string): boolean

---@class FrecencyTelescopePicker
---@field clear_extra_rows fun(self: FrecencyTelescopePicker, results_bufnr: integer): nil
---@field get_row fun(self: FrecencyTelescopePicker, index: integer): integer
---@field manager FrecencyTelescopeEntryManager|false
---@field prompt_bufnr integer
---@field prompt_prefix string
---@field results_bufnr? integer
---@field results_win? integer
---@field sorting_strategy "ascending"|"descending"

---@class FrecencyTelescopeEntryManager
---@field num_results fun(): integer

-- NOTE: types for default functions

---@class UvFsEventHandle
---@field stop fun(self: UvFsEventHandle): nil
---@field start fun(self: UvFsEventHandle, path: string, opts: { recursive: boolean }, cb: fun(err?: string, filename?: string, events: string[])): nil
---@field close fun(self: UvFsEventHandle): nil

--- @class VimSystemObj
--- @field pid integer
--- @field wait fun(self: VimSystemObj, timeout?: integer): VimSystemCompleted
--- @field kill fun(self: VimSystemObj, signal: integer|string)
--- @field write fun(self: VimSystemObj, data?: string|string[])
--- @field is_closing fun(self: VimSystemObj): boolean?

--- @class VimSystemCompleted
--- @field code integer
--- @field signal integer
--- @field stdout? string
--- @field stderr? string

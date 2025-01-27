-- luacheck: no max comment line length
-- luacheck: no unused

---@diagnostic disable: unused-local, missing-return

-- NOTE: types are borrowed from plenary.nvim

---@class FrecencyPlenaryJob
---@field new fun(self: FrecencyPlenaryJob, opts: FrecencyPlenaryJobOpts): FrecencyPlenaryJob
---@field start fun(self: FrecencyPlenaryJob): nil
---@field handle VimSystemObj uv_process_t

---@class FrecencyPlenaryJobOpts
---@field cwd? string
---@field command? string
---@field args? string[]
---@field on_stdout? FrecencyPlenaryJobCallback
---@field on_stderr? FrecencyPlenaryJobCallback

---@alias FrecencyPlenaryJobCallback fun(error: string, data: string, self?: FrecencyPlenaryJob)

---@class FrecencyPlenaryPath
---@field new fun(self: FrecencyPlenaryPath|string, path?: string): FrecencyPlenaryPath
---@field absolute fun(): string
---@field exists fun(self: FrecencyPlenaryPath): boolean
---@field is_file fun(self: FrecencyPlenaryPath): boolean
---@field filename string
---@field joinpath fun(self: FrecencyPlenaryPath, ...): FrecencyPlenaryPath
---@field make_relative fun(self: FrecencyPlenaryPath, cwd: string): string
---@field parent fun(self: FrecencyPlenaryPath): FrecencyPlenaryPath
---@field path { sep: string }
---@field rename fun(self: FrecencyPlenaryPath, opts: { new_name: string }): nil
---@field rm fun(self: FrecencyPlenaryPath, opts?: { recursive: boolean }): nil
---@field touch fun(self: FrecencyPlenaryPath, opts?: { parents: boolean }): nil

---@class FrecencyPlenaryScanDirOptions
---@field hidden boolean if true hidden files will be added
---@field add_dirs boolean if true dirs will also be added to the results
---@field only_dirs boolean if true only dirs will be added to the results
---@field respect_gitignore boolean if true will only add files that are not ignored by the git
---@field depth integer depth on how deep the search should go
---@field search_pattern string|string[]|fun(path: string): boolean regex for which files will be added, string, table of strings, or fn(e) -> boolean
---@field on_insert fun(path: string): boolean           Will be called for each element
---@field silent boolean              if true will not echo messages that are not accessible

---@alias scan_dir fun(path: string, opts: FrecencyPlenaryScanDirOptions): string[]

---@class FrecencyPlenaryAsync
---@field control FrecencyPlenaryAsyncControl
---@field tests { add_to_env: fun(): nil }
---@field util FrecencyPlenaryAsyncUtil
---@field uv FrecencyPlenaryAsyncUv
---@field void fun(f: fun(): nil): fun(): nil
---@field wrap fun(f: (fun(...): any), args: integer): (fun(...): any)
local FrecencyPlenaryAsync = {}

---@async
---@param f fun(): nil
---@return nil
function FrecencyPlenaryAsync.run(f) end

---@class FrecencyPlenaryAsyncControl
---@field channel FrecencyPlenaryAsyncControlChannel

---@class FrecencyPlenaryAsyncControlChannel
---@field mpsc fun(): FrecencyPlenaryAsyncControlChannelTx, FrecencyPlenaryAsyncControlChannelRx
---@field counter fun(): FrecencyPlenaryAsyncControlChannelTx, FrecencyPlenaryAsyncControlChannelRx
local FrecencyPlenaryAsyncControlChannel

---@return fun(...): nil tx
---@return async fun(): ... rx
function FrecencyPlenaryAsyncControlChannel.oneshot() end

---@class FrecencyPlenaryAsyncControlChannelTx
---@field send fun(entry?: any): nil
local FrecencyPlenaryAsyncControlChannelTx = {}

---@class FrecencyPlenaryAsyncControlChannelRx
local FrecencyPlenaryAsyncControlChannelRx = {}

---@async
---@return any?
function FrecencyPlenaryAsyncControlChannelRx.recv() end

---@async
---@return any?
function FrecencyPlenaryAsyncControlChannelRx.last() end

---@class FrecencyPlenaryAsyncUtil
local FrecencyPlenaryAsyncUtil = {}

---@class FrecencyPlenaryAsyncUv
local FrecencyPlenaryAsyncUv = {}

---@class FsStatMtime
---@field sec integer
---@field nsec integer

---@class FsStat
---@field mtime FsStatMtime
---@field size integer
---@field type "file"|"directory"

---@async
---@param path string
---@return string? err
---@return { mtime: FsStatMtime, size: integer, type: "file"|"directory" }
function FrecencyPlenaryAsyncUv.fs_stat(path) end

---@async
---@param path string
---@param flags string|integer
---@param mode integer
---@return string? err
---@return integer fd
function FrecencyPlenaryAsyncUv.fs_open(path, flags, mode) end

---@async
---@param path string
---@return string? err
---@return string? path
function FrecencyPlenaryAsyncUv.fs_realpath(path) end

---@async
---@param fd integer
---@param size integer
---@param offset? integer
---@return string? err
---@return string data
function FrecencyPlenaryAsyncUv.fs_read(fd, size, offset) end

---@async
---@param fd integer
---@param data string
---@param offset? integer
---@return string? err
---@return integer bytes
function FrecencyPlenaryAsyncUv.fs_write(fd, data, offset) end

---@async
---@param path string
---@return string? err
---@return boolean? success
function FrecencyPlenaryAsyncUv.fs_unlink(path) end

---@async
---@param fd integer
---@return string? err
function FrecencyPlenaryAsyncUv.fs_close(fd) end

---@async
---@param async_fns (async fun(...): ...)[]
---@return table
function FrecencyPlenaryAsyncUtil.join(async_fns) end

---@async
---@param ms integer
---@return nil
function FrecencyPlenaryAsyncUtil.sleep(ms) end

---@async
---@return nil
function FrecencyPlenaryAsyncUtil.scheduler() end

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
---@field file_extension fun(filename: string): string

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

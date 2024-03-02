local async = require "plenary.async" --[[@as PlenaryAsync]]
local worker = require "frecency.database.async.worker"

---@class FrecencyWorkJob
---@field id integer
---@field data any

---@class FrecencyWorkJobResult
---@field job_id integer
---@field err string?
---@field result any

---@class FrecencyWorkContext
---@field queue fun(self: FrecencyWorkContext, job: FrecencyWorkJob) boolean|string

---@class FrecencyWork
---@field senders table<integer, fun(entry?: any): nil>
---@field private job_id integer
---@field private ctx FrecencyWorkContext
local Work = {}

local uv = vim.uv or vim.loop

---@param work_callback fun(data: any): string?, any
Work.new = function(work_callback)
  local self = setmetatable({ job_id = 0, senders = {} }, { __index = Work })
  self.ctx = uv.new_work(worker, function(job, err, encoded)
    print(job, err)
    local result = require("string.buffer").decode(encoded)
    if self.senders[job.id] then
      self.senders[job.id] { err, result }
    else
      error "tx not found"
    end
  end)
  return self
end

---@async
---@param data FrecencyAsyncDatabaseJobData
function Work:run(data)
  self.job_id = self.job_id + 1
  local tx, rx = async.control.channel.oneshot()
  self.senders[self.job_id] = tx
  ---@type FrecencyWorkJob
  local job = { id = self.job_id, data = data }
  local encoded = require("string.buffer").encode(job)
  self.ctx:queue(encoded)
  local value = rx()
  local err = value[1]
  local result = value[2]
  return err, result
end

---@param data FrecencyAsyncDatabaseJobData
---@return nil
function Work:void(data)
  async.void(function()
    self:run(data)
  end)()
end

return Work

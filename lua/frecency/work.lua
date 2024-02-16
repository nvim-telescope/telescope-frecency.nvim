local async = require "plenary.async" --[[@as PlenaryAsync]]

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
---@field senders table<integer, PlenaryAsyncControlChannelTx>
---@field private job_id integer
---@field private ctx FrecencyWorkContext
local Work = {}

local uv = vim.uv or vim.loop

---@param work_callback fun(data: any): string?, any
Work.new = function(work_callback)
  local self = setmetatable({ job_id = 0, senders = {} }, { __index = Work })
  self.ctx = uv.new_work(function(job)
    local err, result = work_callback(job.data)
    return job, err, result
  end, function(job, err, result)
    if self.senders[job.id] then
      self.senders[job.id].send { err, result }
    else
      error "tx not found"
    end
  end)
  return self
end

---@async
---@param data any
function Work:run(data)
  self.job_id = self.job_id + 1
  local tx, rx = async.control.channel.oneshot()
  self.senders[self.job_id] = tx
  ---@type FrecencyWorkJob
  local job = { id = self.job_id, data = data }
  self.ctx:queue(job)
  local value = rx.recv()
  local err = value[1]
  local result = value[2]
  return err, result
end

---@param data any
---@return nil
function Work:void(data)
  async.void(function()
    self:run(data)
  end)()
end

return Work

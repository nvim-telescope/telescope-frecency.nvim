local config = require "frecency.config"
local entry = require "frecency.v1.entry"

describe("frecency.entry", function()
  for _, c in ipairs {
    { count = 1, ages = { 200 }, score = 10 },
    { count = 2, ages = { 200, 1000 }, score = 36 },
    { count = 3, ages = { 200, 1000, 4000 }, score = 72 },
    { count = 4, ages = { 200, 1000, 4000, 10000 }, score = 112 },
    { count = 5, ages = { 200, 1000, 4000, 10000, 40000 }, score = 150 },
    { count = 6, ages = { 200, 1000, 4000, 10000, 40000, 100000 }, score = 186 },
    { count = 86, ages = { 11770, 11769, 11431, 5765, 3417, 3398, 3378, 134, 130, 9 }, score = 4988 },
  } do
    local dumped = vim.inspect(c.ages, { indent = "", newline = "" })
    it(("%d, %s => %d"):format(c.count, dumped, c.score), function()
      assert.are.same(c.score, c.count * entry.calculate(c.ages) / config.max_timestamps)
    end)
  end
end)

local const = require("frecency.const")
local algo = {}

algo.calculate_file_score = function (file)
  if file.count == 0 then
    return 0
  end
  local recency_score = 0
  for _, ts in pairs(file.timestamps) do
    for _, rank in ipairs(const.recency_modifier) do
      if ts.age <= rank.age then
        recency_score = recency_score + rank.value
        goto continue
      end
    end
    ::continue::
  end
  return file.count * recency_score / const.max_timestamps
end

return algo

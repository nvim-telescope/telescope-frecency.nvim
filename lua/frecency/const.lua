return {
  max_timestamps = 10,
  db_remove_safety_threshold = 10,
  -- modifier used as a weight in the recency_score calculation:
  recency_modifier = {
    [1] = { age = 240, value = 100 }, -- past 4 hours
    [2] = { age = 1440, value = 80 }, -- past day
    [3] = { age = 4320, value = 60 }, -- past 3 days
    [4] = { age = 10080, value = 40 }, -- past week
    [5] = { age = 43200, value = 20 }, -- past month
    [6] = { age = 129600, value = 10 }, -- past 90 days
  },
  ignore_patterns = {
    "*.git/*",
    "*/tmp/*",
  },
}

---@param module string
return function(module)
  return setmetatable({}, {
    __index = function(_, key)
      return require(module)[key]
    end,
    __call = function(_, ...)
      return require(module)(...)
    end,
  })
end

local frecency = require "frecency"

return require("telescope").register_extension {
  setup = frecency.setup,
  exports = {
    frecency = frecency.start,
    complete = frecency.complete,
  },
}

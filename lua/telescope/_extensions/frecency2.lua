local frecency = require "frecency"

return require("telescope").register_extension {
  setup = frecency.setup,
  exports = {
    frecency2 = frecency.start,
    complete = frecency.complete,
  },
}

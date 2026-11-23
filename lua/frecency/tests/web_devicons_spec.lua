local web_devicons = require "frecency.web_devicons"

describe("frecency.web_devicons", function()
  describe("file_extension", function()
    for _, c in ipairs {
      { "main.c", "c" },
      { "foo.test.js", "test.js" },
      { "a.b.c.d", "c.d" },
      { "Makefile", "Makefile" },
      { ".bashrc", "bashrc" },
    } do
      local filename, expected = c[1], c[2]
      it(("returns %q for %q"):format(expected, filename), function()
        assert.are.same(expected, web_devicons.file_extension(filename))
      end)
    end
  end)
end)

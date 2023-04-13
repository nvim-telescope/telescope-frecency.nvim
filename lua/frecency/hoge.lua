local it, cancel = require("frecency.fs").dir("~", { depth = 3 })
local c = os.clock()
local t = vim.loop.new_timer()
t:start(1000, 0, function()
	t:stop()
	t:close()
	cancel()
	vim.print(vim.inspect({ os.clock() - c, "cancelled!" }, { indent = "", newline = "" }))
end)
local count = 0
for f, t in it do
	count = count + 1
	if count % 1000 == 0 then
		vim.schedule(function() end)
	end
	vim.print({ count, f, t })
end

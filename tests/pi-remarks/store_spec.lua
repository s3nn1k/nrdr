local store = require("pi-remarks.store")

describe("store", function()
	local root
	local other_root

	before_each(function()
		root = vim.fs.normalize(vim.fn.tempname())
		other_root = root .. "-other"
		vim.fn.mkdir(root, "p")
		vim.fn.mkdir(other_root, "p")
	end)

	after_each(function()
		for _, path in ipairs({ store.state_path(root), store.state_path(other_root) }) do
			vim.fn.delete(path)
			vim.fn.delete(path .. ".*.tmp")
		end
		vim.fn.delete(root, "rf")
		vim.fn.delete(other_root, "rf")
	end)

	it("round-trips remarks through disk without a sent field", function()
		local remarks = {
			{
				path = root .. "/src/a.lua",
				relpath = "src/a.lua",
				line_start = 3,
				line_end = 7,
				comment = "первая строка\nвторая строка",
			},
			{
				path = root .. "/b.go",
				relpath = "b.go",
				line_start = 1,
				line_end = 1,
				comment = "одиночный",
			},
		}
		store.save(root, remarks)
		local loaded = store.load(root)
		assert.same(remarks, loaded)
		assert.is_nil(loaded[1].sent)
		assert.same("", vim.fn.glob(store.state_path(root) .. ".*.tmp"))
	end)

	it("returns an empty stack without a saved file", function()
		assert.same({}, store.load(root))
	end)

	it("keeps different project roots apart", function()
		store.save(root, { { relpath = "a" } })
		store.save(other_root, { { relpath = "b" }, { relpath = "c" } })
		assert.same(1, #store.load(root))
		assert.same(2, #store.load(other_root))
	end)

	it("rejects a corrupt file with an error and an empty stack", function()
		local notifications = {}
		local original_notify = vim.notify
		vim.notify = function(message, level)
			table.insert(notifications, { message = message, level = level })
		end
		vim.fn.mkdir(vim.fs.dirname(store.state_path(root)), "p")
		vim.fn.writefile({ "{ not json" }, store.state_path(root))
		local remarks = store.load(root)
		vim.notify = original_notify
		assert.same({}, remarks)
		assert.same(1, #notifications)
		assert.same(vim.log.levels.ERROR, notifications[1].level)
	end)
end)

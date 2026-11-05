local list = require("pi-remarks.list")
local store = require("pi-remarks.store")

describe("list", function()
	local root
	local original_notify
	local notifications
	local original_select
	local select_calls

	local function fixture_remarks()
		return {
			{
				path = root .. "/a.lua",
				relpath = "a.lua",
				line_start = 1,
				line_end = 2,
				comment = "первое",
				sent = false,
			},
			{
				path = root .. "/b.go",
				relpath = "b.go",
				line_start = 5,
				line_end = 5,
				comment = "второе",
				sent = true,
			},
		}
	end

	local function list_bufnr()
		return vim.fn.bufnr("^pi-remarks://" .. root .. "$")
	end

	local function feed(keys)
		vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "mx", false)
	end

	local function close_list()
		local bufnr = list_bufnr()
		if bufnr >= 0 then
			for _, win in ipairs(vim.fn.win_findbuf(bufnr)) do
				pcall(vim.api.nvim_win_close, win, true)
			end
			pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
		end
	end

	local function close_popup_if_any()
		local bufnr = vim.api.nvim_get_current_buf()
		if vim.api.nvim_buf_is_loaded(bufnr) and vim.bo[bufnr].buftype == "nofile" and bufnr ~= list_bufnr() then
			for _, win in ipairs(vim.fn.win_findbuf(bufnr)) do
				pcall(vim.api.nvim_win_close, win, true)
			end
			pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
		end
	end

	before_each(function()
		root = vim.fs.normalize(vim.fn.tempname())
		store.save(root, fixture_remarks())
		original_notify = vim.notify
		notifications = {}
		vim.notify = function(message, level)
			table.insert(notifications, { message = message, level = level })
		end
		original_select = vim.ui.select
		select_calls = {}
		vim.ui.select = function(items, opts, on_choice)
			table.insert(select_calls, { items = items, on_choice = on_choice })
		end
	end)

	after_each(function()
		close_popup_if_any()
		close_list()
		vim.notify = original_notify
		vim.ui.select = original_select
		vim.fn.delete(store.state_path(root))
		vim.fn.delete(root, "rf")
	end)

	it("renders sent marks and relpath ranges", function()
		list.open(root)
		local lines = vim.api.nvim_buf_get_lines(list_bufnr(), 0, -1, false)
		assert.same(2, #lines)
		assert.truthy(lines[1]:find("^%[ %] a%.lua:1%-2 первое"))
		assert.truthy(lines[2]:find("^%[x%] b%.go:5%-5 второе"))
	end)

	it("deletes the remark under the cursor with d", function()
		list.open(root)
		vim.api.nvim_win_set_cursor(0, { 1, 0 })
		feed("d")
		local remarks = store.load(root)
		assert.same(1, #remarks)
		assert.same("b.go", remarks[1].relpath)
		local lines = vim.api.nvim_buf_get_lines(list_bufnr(), 0, -1, false)
		assert.same(1, #lines)
		assert.truthy(lines[1]:find("^%[x%] b%.go:5%-5"))
	end)

	it("ignores d when the cursor points past a shrunken stack", function()
		list.open(root)
		vim.api.nvim_win_set_cursor(0, { 2, 0 })
		store.save(root, { fixture_remarks()[1] })
		feed("d")
		assert.same(1, #store.load(root))
		assert.same(2, #vim.api.nvim_buf_get_lines(list_bufnr(), 0, -1, false))
		assert.same(0, #notifications)
	end)

	it("ignores d on an empty stack", function()
		store.save(root, {})
		list.open(root)
		feed("d")
		assert.same(0, #store.load(root))
		assert.same(0, #notifications)
	end)

	it("edits the comment through the same popup with e", function()
		list.open(root)
		vim.api.nvim_win_set_cursor(0, { 1, 0 })
		feed("e")
		assert.same({ "первое" }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
		vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.split("исправленное\nзамечание", "\n"))
		feed("ZZ")
		local remarks = store.load(root)
		assert.same(2, #remarks)
		assert.same("исправленное\nзамечание", remarks[1].comment)
		local lines = vim.api.nvim_buf_get_lines(list_bufnr(), 0, -1, false)
		assert.truthy(lines[1]:find("^%[ %] a%.lua:1%-2 исправленное"))
	end)

	it("clears the stack through confirm with C", function()
		list.open(root)
		feed("C")
		assert.same(1, #select_calls)
		assert.same(2, #select_calls[1].items)
		select_calls[1].on_choice(true)
		assert.same(0, #store.load(root))
		assert.same({ "" }, vim.api.nvim_buf_get_lines(list_bufnr(), 0, -1, false))
	end)

	it("keeps the stack when confirm is declined with C", function()
		list.open(root)
		feed("C")
		select_calls[1].on_choice(false)
		assert.same(2, #store.load(root))
		assert.same(2, #vim.api.nvim_buf_get_lines(list_bufnr(), 0, -1, false))
	end)

	it("does not open confirm on an empty stack with C", function()
		store.save(root, {})
		list.open(root)
		feed("C")
		assert.same(0, #select_calls)
	end)
end)

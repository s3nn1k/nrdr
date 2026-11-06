local popup = require("pi-remarks.popup")

describe("popup", function()
	local original_notify
	local notifications

	local function open(options)
		local confirmed = {}
		popup.open(vim.tbl_extend("force", {
			on_confirm = function(text)
				table.insert(confirmed, text)
			end,
		}, options or {}))
		return confirmed
	end

	local function feed(keys)
		vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "mx", false)
	end

	local function popup_bufnr()
		return vim.api.nvim_get_current_buf()
	end

	local function close_popup()
		local bufnr = popup_bufnr()
		if vim.api.nvim_buf_is_loaded(bufnr) and vim.bo[bufnr].buftype == "nofile" then
			for _, win in ipairs(vim.fn.win_findbuf(bufnr)) do
				pcall(vim.api.nvim_win_close, win, true)
			end
			pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
		end
	end

	before_each(function()
		original_notify = vim.notify
		notifications = {}
		vim.notify = function(message, level)
			table.insert(notifications, { message = message, level = level })
		end
	end)

	after_each(function()
		vim.notify = original_notify
		close_popup()
	end)

	it("notifies and stays open on ZZ with an empty comment", function()
		local confirmed = open()
		feed("ZZ")
		assert.same({}, confirmed)
		assert.same(1, #notifications)
		assert.same(vim.log.levels.ERROR, notifications[1].level)
		assert.truthy(notifications[1].message:find("пустой комментарий", 1, true))
		assert.truthy(vim.api.nvim_buf_is_loaded(popup_bufnr()))
	end)

	it("confirms the joined buffer text on ZZ and drops trailing empty lines", function()
		local confirmed = open()
		local bufnr = popup_bufnr()
		vim.api.nvim_buf_set_lines(
			bufnr,
			0,
			-1,
			false,
			{ "первая строка", "вторая строка", "" }
		)
		feed("ZZ")
		assert.same({ "первая строка\nвторая строка" }, confirmed)
		assert.is_false(vim.api.nvim_buf_is_loaded(bufnr))
	end)

	it("cancels with on_confirm(nil) on q", function()
		local confirmed = open()
		local bufnr = popup_bufnr()
		vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "черновик" })
		feed("q")
		assert.same({ nil }, confirmed)
		assert.is_false(vim.api.nvim_buf_is_loaded(bufnr))
	end)

	it("cancels the active popup when opened again and serves only the new one", function()
		local stale = open({ initial = "старый текст" })
		local current = open()
		assert.same({ nil }, stale)
		assert.same({}, current)
		vim.api.nvim_buf_set_lines(popup_bufnr(), 0, -1, false, { "новый текст" })
		feed("ZZ")
		assert.same({ nil }, stale)
		assert.same({ "новый текст" }, current)
	end)

	it("cancels with on_confirm(nil) when the popup buffer is wiped", function()
		local confirmed = open()
		vim.api.nvim_buf_delete(popup_bufnr(), { force = true })
		assert.same({ nil }, confirmed)
	end)

	it("styles the floating window with a neutral title highlight", function()
		open({ initial = "x" })
		local win = vim.api.nvim_get_current_win()
		local config = vim.api.nvim_win_get_config(win)
		assert.same(" comment ", config.title[1][1])
		assert.same("FloatTitle:NormalFloat", vim.wo[win].winhighlight)
		feed("q")
	end)
end)

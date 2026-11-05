local popup = require("pi-remarks.popup")
local store = require("pi-remarks.store")

local M = {}

local preview_width = 60
local list_height = 12

local function buffer_name(root)
	return "pi-remarks://" .. root
end

local function preview_text(comment)
	local first_line = vim.split(comment, "\n", { trimempty = true })[1] or ""
	if #first_line > preview_width then
		return first_line:sub(1, preview_width - 1) .. "…"
	end
	return first_line
end

local function render(bufnr, root)
	local remarks = store.load(root)
	local lines = {}
	for index, remark in ipairs(remarks) do
		lines[index] = ("%s %s:%d-%d %s"):format(
			remark.sent and "[x]" or "[ ]",
			remark.rel,
			remark.line_start,
			remark.line_end,
			preview_text(remark.comment)
		)
	end
	vim.bo[bufnr].modifiable = true
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
	vim.bo[bufnr].modified = false
	vim.bo[bufnr].modifiable = false
end

local function jump(remark)
	local file_bufnr = vim.fn.bufnr(remark.path)
	local wins = file_bufnr > 0 and vim.fn.win_findbuf(file_bufnr) or {}
	if wins[1] then
		vim.api.nvim_set_current_win(wins[1])
	else
		vim.cmd.split(vim.fn.fnameescape(remark.path))
	end
	vim.api.nvim_win_set_cursor(0, { remark.line_start, 0 })
end

local function confirm(message, on_choice)
	vim.ui.select({ false, true }, {
		prompt = message,
		format_item = function(choice)
			return choice and "да" or "нет"
		end,
	}, on_choice)
end

local function set_keymaps(bufnr, root)
	vim.keymap.set("n", "d", function()
		local remarks = store.load(root)
		local index = vim.api.nvim_win_get_cursor(0)[1]
		if not remarks[index] then
			return
		end
		table.remove(remarks, index)
		store.save(root, remarks)
		render(bufnr, root)
	end, { buffer = bufnr, desc = "pi-remarks: удалить замечание" })

	vim.keymap.set("n", "e", function()
		local remarks = store.load(root)
		local index = vim.api.nvim_win_get_cursor(0)[1]
		if not remarks[index] then
			return
		end
		popup.open({
			initial = remarks[index].comment,
			on_confirm = function(comment)
				if not comment then
					return
				end
				remarks = store.load(root)
				if not remarks[index] then
					return
				end
				remarks[index].comment = comment
				store.save(root, remarks)
				render(bufnr, root)
			end,
		})
	end, { buffer = bufnr, desc = "pi-remarks: изменить комментарий" })

	vim.keymap.set("n", "<CR>", function()
		local remark = store.load(root)[vim.api.nvim_win_get_cursor(0)[1]]
		if not remark then
			return
		end
		jump(remark)
	end, { buffer = bufnr, desc = "pi-remarks: перейти к файлу" })

	vim.keymap.set("n", "S", function()
		require("pi-remarks").send_unsent(root)
	end, { buffer = bufnr, desc = "pi-remarks: отправить неотправленные" })

	vim.keymap.set("n", "C", function()
		local remarks = store.load(root)
		if #remarks == 0 then
			return
		end
		confirm(("удалить все замечания (%d)?"):format(#remarks), function(confirmed)
			if not confirmed then
				return
			end
			remarks = store.load(root)
			for index = #remarks, 1, -1 do
				remarks[index] = nil
			end
			store.save(root, remarks)
			render(bufnr, root)
		end)
	end, { buffer = bufnr, desc = "pi-remarks: очистить всё" })
end

function M.open(root)
	local name = buffer_name(root)
	local bufnr = vim.fn.bufnr("^" .. name .. "$")
	if bufnr < 0 then
		bufnr = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_name(bufnr, name)
		vim.bo[bufnr].buftype = "nofile"
		vim.bo[bufnr].bufhidden = "hide"
		vim.bo[bufnr].swapfile = false
		vim.bo[bufnr].filetype = "pi-remarks"
		set_keymaps(bufnr, root)
	end
	render(bufnr, root)
	local existing_win = vim.fn.win_findbuf(bufnr)[1]
	if existing_win then
		vim.api.nvim_set_current_win(existing_win)
		return
	end
	vim.api.nvim_open_win(bufnr, true, {
		split = "below",
		win = vim.api.nvim_get_current_win(),
		height = math.min(list_height, vim.o.lines - 2),
	})
end

function M.refresh(root)
	local bufnr = vim.fn.bufnr("^" .. buffer_name(root) .. "$")
	if bufnr >= 0 and vim.api.nvim_buf_is_loaded(bufnr) then
		render(bufnr, root)
	end
end

return M

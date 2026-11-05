local M = {}

local max_width = 80
local max_height = 10

local active = nil

local function read_text(bufnr)
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	while #lines > 0 and lines[#lines] == "" do
		table.remove(lines)
	end
	return table.concat(lines, "\n")
end

local function close(state)
	if state.win and vim.api.nvim_win_is_valid(state.win) then
		vim.api.nvim_win_close(state.win, true)
	end
	if state.buf and vim.api.nvim_buf_is_loaded(state.buf) then
		vim.api.nvim_buf_delete(state.buf, { force = true })
	end
end

local function finish(state, text)
	if active ~= state then
		return
	end
	active = nil
	close(state)
	state.on_confirm(text)
end

function M.open(opts)
	if active then
		local stale = active
		active = nil
		close(stale)
		stale.on_confirm(nil)
	end
	local bufnr = vim.api.nvim_create_buf(false, true)
	vim.bo[bufnr].buftype = "nofile"
	vim.bo[bufnr].bufhidden = "wipe"
	vim.bo[bufnr].swapfile = false
	if opts.initial then
		vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(opts.initial, "\n"))
	end
	local state = { buf = bufnr, win = nil, on_confirm = opts.on_confirm }
	active = state
	vim.keymap.set("n", "ZZ", function()
		local text = read_text(bufnr)
		if vim.trim(text) == "" then
			vim.notify("pi-remarks: пустой комментарий", vim.log.levels.ERROR)
			return
		end
		finish(state, text)
	end, { buffer = bufnr, desc = "pi-remarks: подтвердить комментарий" })
	vim.keymap.set("n", "ZQ", function()
		finish(state, nil)
	end, { buffer = bufnr, desc = "pi-remarks: отменить комментарий" })
	vim.api.nvim_create_autocmd("BufWipeout", {
		buffer = bufnr,
		callback = function()
			if active == state then
				active = nil
				state.on_confirm(nil)
			end
		end,
	})
	local width = math.min(max_width, vim.o.columns - 4)
	local height = math.min(max_height, vim.o.lines - 4)
	state.win = vim.api.nvim_open_win(bufnr, true, {
		relative = "editor",
		width = width,
		height = height,
		row = math.floor((vim.o.lines - height) / 2),
		col = math.floor((vim.o.columns - width) / 2),
		border = "rounded",
		title = " замечание ",
		title_pos = "center",
	})
end

return M

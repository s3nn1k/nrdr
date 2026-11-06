local M = {}

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
			vim.notify("nrdr: пустой комментарий", vim.log.levels.ERROR)
			return
		end
		finish(state, text)
	end, { buffer = bufnr, desc = "nrdr: подтвердить комментарий" })
	vim.keymap.set("n", "q", function()
		finish(state, nil)
	end, { buffer = bufnr, desc = "nrdr: отменить комментарий" })
	vim.api.nvim_create_autocmd("BufWipeout", {
		buffer = bufnr,
		callback = function()
			if active == state then
				active = nil
				state.on_confirm(nil)
			end
		end,
	})
	local width = math.max(24, math.floor(vim.o.columns * 0.4))
	local height = math.max(6, math.floor(vim.o.lines * 0.6))
	state.win = vim.api.nvim_open_win(bufnr, true, {
		relative = "editor",
		width = width,
		height = height,
		row = math.floor((vim.o.lines - height) / 2),
		col = math.floor((vim.o.columns - width) / 2),
		border = "rounded",
		title = " comment ",
		title_pos = "center",
	})
	vim.wo[state.win].winhighlight = "FloatTitle:NormalFloat"
end

return M

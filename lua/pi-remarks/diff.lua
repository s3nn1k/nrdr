local util = require("pi-remarks.util")

local M = {}

function M.parse_hunks(diff_text)
	local hunks = {}
	local current = nil
	for line in diff_text:gmatch("[^\n]+") do
		local new_start, new_count = line:match("^@@ %-%d+,?%d* %+(%d+),?(%d*)")
		if new_start then
			if current then
				hunks[#hunks + 1] = current
			end
			current = {
				new_start = tonumber(new_start),
				new_count = tonumber(new_count) or 1,
				header = line,
				body = {},
			}
		elseif current then
			table.insert(current.body, line)
		end
	end
	if current then
		hunks[#hunks + 1] = current
	end
	return hunks
end

function M.select_hunk(hunks, line_start, line_end)
	for _, hunk in ipairs(hunks) do
		local hunk_end = hunk.new_start + hunk.new_count - 1
		if line_start <= hunk_end and hunk.new_start <= line_end then
			return hunk
		end
	end
	return nil
end

local hunk_context_window = 10

function M.trim_body(matched, line_start, line_end)
	local new_start = tonumber(matched.header:match("^@@ %-%d+,?%d* %+(%d+)"))
	local new_count = tonumber(matched.header:match("^@@ %-%d+,?%d* %+%d+,(%d+)")) or 1
	local new_end = new_start + new_count - 1
	local anchor_start = math.max(line_start, new_start)
	local anchor_end = math.min(line_end, new_end)
	local window_start = math.max(anchor_start - hunk_context_window, new_start)
	local window_end = math.min(anchor_end + hunk_context_window, new_end)

	local rows = {}
	local new_line = new_start
	for _, line in ipairs(matched.body) do
		local prefix = line:sub(1, 1)
		local row = { line = line, new_line = new_line }
		if prefix == " " or prefix == "+" then
			rows[#rows + 1] = row
			new_line = new_line + 1
		else
			row.new_line = rows[#rows] and rows[#rows].new_line or new_line
			rows[#rows + 1] = row
		end
	end

	local kept = {}
	for _, row in ipairs(rows) do
		if row.new_line >= window_start and row.new_line <= window_end then
			kept[#kept + 1] = row
		end
	end
	if #kept == 0 then
		return nil
	end

	local body = {}
	if rows[1].new_line < window_start then
		body[#body + 1] = "…"
	end
	for _, row in ipairs(kept) do
		body[#body + 1] = row.line
	end
	if rows[#rows].new_line > window_end then
		body[#body + 1] = "…"
	end

	return { header = matched.header, body = body }
end

function M.match_hunk(diff_text, line_start, line_end)
	local matched = M.select_hunk(M.parse_hunks(diff_text), line_start, line_end)
	if not matched then
		return nil
	end
	return M.trim_body({ header = matched.header, body = matched.body }, line_start, line_end)
end

function M.snapshot(path, line_start, line_end, diff_base)
	local dir = vim.fs.dirname(path)
	local git_path = path
	if git_path:sub(1, #dir + 1) == dir .. "/" then
		git_path = git_path:sub(#dir + 2)
	end
	local done = vim.system(
		{ "git", "-C", dir, "diff", "-U3", diff_base, "--", ":(literal)" .. git_path },
		{ text = true }
	)
		:wait()
	local git_output = (done.stderr or "") .. "\n" .. (done.stdout or "")
	if git_output:find("not a git repository", 1, true) or git_output:find("Could not access", 1, true) then
		return nil
	end
	if done.code ~= 0 then
		vim.notify(
			"pi-remarks: git diff завершился с ошибкой (code "
				.. done.code
				.. "): "
				.. util.snippet(done.stderr),
			vim.log.levels.WARN
		)
		return nil
	end
	return M.match_hunk(done.stdout, line_start, line_end)
end

return M

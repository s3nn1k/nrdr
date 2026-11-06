local M = {}

function M.line_span(remark)
	if remark.line_start == remark.line_end then
		return tostring(remark.line_start)
	end
	return remark.line_start .. "-" .. remark.line_end
end

function M.remark_block(remark)
	local lines = { "файл: " .. remark.path .. ":" .. M.line_span(remark) }
	local comment_lines = vim.split(remark.comment, "\n")
	lines[#lines + 1] = "комментарий: " .. comment_lines[1]
	for index = 2, #comment_lines do
		lines[#lines + 1] = "  " .. comment_lines[index]
	end
	if remark.diff then
		vim.list_extend(lines, remark.diff.body)
	end
	return table.concat(lines, "\n")
end

return M

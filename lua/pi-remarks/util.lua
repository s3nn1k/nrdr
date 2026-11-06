local M = {}

local max_error_snippet = 120

function M.snippet(text)
	local fragment = vim.trim(text or "")
	if #fragment > max_error_snippet then
		return fragment:sub(1, max_error_snippet - 1) .. "…"
	end
	return fragment
end

return M

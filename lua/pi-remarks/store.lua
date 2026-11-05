local M = {}

local function state_dir()
	return vim.fs.normalize(vim.fn.stdpath("state")) .. "/pi-remarks"
end

function M.state_path(root)
	return state_dir() .. "/" .. vim.fn.sha256(root) .. ".json"
end

function M.load(root)
	local path = M.state_path(root)
	local file = io.open(path, "r")
	if not file then
		return {}
	end
	local content = file:read("*a")
	file:close()
	local ok, decoded = pcall(vim.json.decode, content)
	if not ok or type(decoded) ~= "table" then
		vim.notify(
			"pi-remarks: не удалось прочитать " .. path .. ": " .. tostring(decoded),
			vim.log.levels.ERROR
		)
		return {}
	end
	return decoded
end

function M.save(root, remarks)
	local ok, encoded = pcall(vim.json.encode, remarks)
	if not ok then
		vim.notify(
			"pi-remarks: не удалось сериализовать замечания: " .. tostring(encoded),
			vim.log.levels.ERROR
		)
		return
	end
	vim.fn.mkdir(state_dir(), "p")
	vim.fn.writefile({ encoded }, M.state_path(root))
end

return M

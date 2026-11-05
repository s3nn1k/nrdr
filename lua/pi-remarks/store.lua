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
	local path = M.state_path(root)
	local tmp_path = path .. "." .. vim.uv.getpid() .. ".tmp"
	local write_ok, write_err = pcall(vim.fn.writefile, { encoded }, tmp_path)
	if not write_ok then
		vim.notify(
			"pi-remarks: не удалось записать " .. tmp_path .. ": " .. tostring(write_err),
			vim.log.levels.ERROR
		)
		return
	end
	local renamed, rename_err = vim.uv.fs_rename(tmp_path, path)
	if not renamed then
		pcall(vim.uv.fs_unlink, tmp_path)
		vim.notify(
			"pi-remarks: не удалось переместить "
				.. tmp_path
				.. " в "
				.. path
				.. ": "
				.. tostring(rename_err),
			vim.log.levels.ERROR
		)
	end
end

return M

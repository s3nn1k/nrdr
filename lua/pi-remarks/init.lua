local picker = require("pi-remarks.picker")
local popup = require("pi-remarks.popup")
local send = require("pi-remarks.send")
local store = require("pi-remarks.store")

local M = {}

local defaults = {
	herdr_bin = "herdr",
	wait_timeout_ms = 600000,
}

local config = vim.deepcopy(defaults)
local active_waits = {}

local function notify_error(message)
	vim.notify("pi-remarks: " .. message, vim.log.levels.ERROR)
end

local function notify_warn(message)
	vim.notify("pi-remarks: " .. message, vim.log.levels.WARN)
end

local function current_root()
	return vim.fs.normalize(vim.fn.getcwd())
end

local function file_path()
	if vim.bo.buftype ~= "" then
		return nil, "буфер не связан с файлом"
	end
	local path = vim.fs.normalize(vim.api.nvim_buf_get_name(0))
	if path == "" then
		return nil, "буфер не связан с файлом"
	end
	return path, nil
end

function M.setup(opts)
	config = vim.tbl_deep_extend("force", defaults, opts or {})
end

local function open_comment_popup(root, path, line_start, line_end)
	popup.open({
		on_confirm = function(comment)
			if not comment then
				return
			end
			local remarks = store.load(root)
			table.insert(remarks, {
				path = path,
				relpath = vim.fs.relpath(root, path) or path,
				line_start = math.min(line_start, line_end),
				line_end = math.max(line_start, line_end),
				comment = comment,
			})
			store.save(root, remarks)
		end,
	})
end

function M.add_line(count)
	local path, target_error = file_path()
	if target_error then
		notify_error(target_error)
		return
	end
	local root = current_root()
	local line_start = vim.api.nvim_win_get_cursor(0)[1]
	local line_end = line_start + math.max(count, 1) - 1
	open_comment_popup(root, path, line_start, line_end)
end

function M.add_range(line_start, line_end)
	local path, target_error = file_path()
	if target_error then
		notify_error(target_error)
		return
	end
	open_comment_popup(current_root(), path, line_start, line_end)
end

function M.pick()
	picker.remarks(current_root())
end

local function remark_key(remark)
	return remark.path .. "|" .. remark.line_start .. "|" .. remark.line_end .. "|" .. remark.comment
end

local function start_wait(herdr_bin, pane_id, timeout_ms)
	if active_waits[pane_id] then
		notify_warn("уже ждём завершения хода агента (pane " .. pane_id .. ")")
		return
	end
	local handle = send.wait_idle(herdr_bin, pane_id, timeout_ms, function(wait_error)
		active_waits[pane_id] = nil
		if wait_error then
			notify_warn(wait_error)
			return
		end
		vim.notify("pi-remarks: агент завершил ход", vim.log.levels.INFO)
	end)
	if handle then
		active_waits[pane_id] = handle
	end
end

local function deliver(root, remarks_to_send)
	local message = send.build_message(remarks_to_send)
	local agents, list_error = send.list_agents(config.herdr_bin)
	if list_error then
		notify_error(list_error)
		return
	end
	if #agents == 0 then
		notify_error("агенты herdr не найдены")
		return
	end
	local sent_keys = {}
	for _, remark in ipairs(remarks_to_send) do
		sent_keys[remark_key(remark)] = true
	end
	picker.agent(agents, root, function(pane_id)
		if not pane_id then
			return
		end
		send.prompt(config.herdr_bin, pane_id, message, function(prompt_error)
			if prompt_error then
				notify_error(prompt_error)
				return
			end
			local remarks = store.load(root)
			local kept = {}
			for _, remark in ipairs(remarks) do
				if not sent_keys[remark_key(remark)] then
					kept[#kept + 1] = remark
				end
			end
			store.save(root, kept)
			vim.notify(("pi-remarks: отправлено (pane %s)"):format(pane_id), vim.log.levels.INFO)
			start_wait(config.herdr_bin, pane_id, config.wait_timeout_ms)
		end)
	end)
end

function M.send(root)
	local target_root = root or current_root()
	local remarks = store.load(target_root)
	if #remarks == 0 then
		notify_error("замечаний нет")
		return
	end
	deliver(target_root, remarks)
end

vim.api.nvim_create_user_command("PiRemarks", function()
	M.pick()
end, {})

vim.api.nvim_create_autocmd("VimLeavePre", {
	callback = function()
		for _, handle in pairs(active_waits) do
			pcall(handle.kill, handle, "term")
		end
	end,
})

return M

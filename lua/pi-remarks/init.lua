local list = require("pi-remarks.list")
local popup = require("pi-remarks.popup")
local send = require("pi-remarks.send")
local store = require("pi-remarks.store")

local M = {}

local defaults = {
	herdr_bin = "herdr",
	wait_timeout_ms = 600000,
}

local config = vim.deepcopy(defaults)

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

function M.add(line_start, line_end)
	local path, target_error = file_path()
	if target_error then
		notify_error(target_error)
		return
	end
	local root = current_root()
	popup.open({
		on_confirm = function(comment)
			if not comment then
				return
			end
			local remarks = store.load(root)
			table.insert(remarks, {
				path = path,
				rel = vim.fs.relpath(root, path) or path,
				line_start = math.min(line_start, line_end),
				line_end = math.max(line_start, line_end),
				comment = comment,
				sent = false,
			})
			store.save(root, remarks)
		end,
	})
end

function M.open_list()
	list.open(current_root())
end

local function deliver(root, stack, remarks_to_send)
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
	send.select_agent(agents, root, function(pane_id)
		if not pane_id then
			return
		end
		send.prompt(config.herdr_bin, pane_id, message, function(prompt_error)
			if prompt_error then
				notify_error(prompt_error)
				return
			end
			for _, remark in ipairs(remarks_to_send) do
				remark.sent = true
			end
			store.save(root, stack)
			list.refresh(root)
			vim.notify(("pi-remarks: отправлено (pane %s)"):format(pane_id), vim.log.levels.INFO)
			send.wait_idle(config.herdr_bin, pane_id, config.wait_timeout_ms, function(wait_error)
				if wait_error then
					notify_warn(wait_error)
					return
				end
				vim.notify("pi-remarks: агент завершил ход", vim.log.levels.INFO)
			end)
		end)
	end)
end

function M.send_all()
	local root = current_root()
	local stack = store.load(root)
	if #stack == 0 then
		notify_error("замечаний нет")
		return
	end
	deliver(root, stack, stack)
end

function M.send_unsent(root)
	local stack = store.load(root)
	local unsent = vim.tbl_filter(function(remark)
		return not remark.sent
	end, stack)
	if #unsent == 0 then
		notify_error("неотправленных замечаний нет")
		return
	end
	deliver(root, stack, unsent)
end

vim.api.nvim_create_user_command("PiRemarksAdd", function(command)
	M.add(command.line1, command.line2)
end, { range = true })

vim.api.nvim_create_user_command("PiRemarks", function()
	M.open_list()
end, {})

vim.api.nvim_create_user_command("PiRemarksSend", function()
	M.send_all()
end, {})

return M

local popup = require("pi-remarks.popup")
local store = require("pi-remarks.store")

local M = {}

local function telescope_available()
	return pcall(require, "telescope.pickers")
end

local function remark_line(remark)
	if remark.line_start == remark.line_end then
		return tostring(remark.line_start)
	end
	return remark.line_start .. "-" .. remark.line_end
end

function M.remark_entry(remark)
	return remark.relpath .. ":" .. remark_line(remark)
end

function M.remark_entry_with_preview(remark)
	local first_line = vim.split(remark.comment, "\n", { trimempty = true })[1] or ""
	return M.remark_entry(remark) .. " " .. first_line
end

function M.agent_entry(agent)
	local name = agent.name
	if not name or name == "" then
		name = agent.terminal_title_stripped
	end
	if not name or name == "" then
		name = "?"
	end
	return ("%s · %s · %s · %s"):format(name, agent.cwd or "?", agent.agent_status or "?", agent.pane_id or "?")
end

function M.sort_agents(agents, root)
	local indexed = {}
	for index, agent in ipairs(agents) do
		indexed[index] = { agent = agent, order = index }
	end
	table.sort(indexed, function(a, b)
		local a_match = vim.fs.normalize(a.agent.cwd or "") == root
		local b_match = vim.fs.normalize(b.agent.cwd or "") == root
		if a_match ~= b_match then
			return a_match
		end
		return a.order < b.order
	end)
	local sorted = {}
	for index, pair in ipairs(indexed) do
		sorted[index] = pair.agent
	end
	return sorted
end

local function clamped_line(remark, bufnr)
	local line_count = vim.api.nvim_buf_line_count(bufnr)
	return math.max(1, math.min(remark.line_start, line_count))
end

local function jump(remark)
	local file_bufnr = vim.fn.bufnr(remark.path)
	local wins = file_bufnr > 0 and vim.fn.win_findbuf(file_bufnr) or {}
	if wins[1] then
		vim.api.nvim_set_current_win(wins[1])
		vim.api.nvim_win_set_cursor(wins[1], { clamped_line(remark, file_bufnr), 0 })
		return
	end
	if vim.fn.filereadable(remark.path) == 0 then
		vim.notify(
			"pi-remarks: файл замечания не существует: " .. remark.relpath,
			vim.log.levels.WARN
		)
		return
	end
	vim.cmd.edit(vim.fn.fnameescape(remark.path))
	vim.api.nvim_win_set_cursor(0, { clamped_line(remark, 0), 0 })
end

local function remark_results()
	local results = {}
	for index, remark in ipairs(store.all()) do
		results[index] = { index = index, remark = remark }
	end
	return results
end

local function remark_finder(finder)
	return finder.new_table({
		results = remark_results(),
		entry_maker = function(entry)
			return {
				value = entry,
				display = function()
					return M.remark_entry(entry.remark)
				end,
				ordinal = M.remark_entry(entry.remark),
			}
		end,
	})
end

local function remark_previewer(previewers)
	return previewers.new_buffer_previewer({
		title = " comment ",
		define_preview = function(self, entry)
			vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, vim.split(entry.value.remark.comment, "\n"))
		end,
	})
end

local function telescope_remarks()
	local pickers = require("telescope.pickers")
	local finders = require("telescope.finders")
	local actions = require("telescope.actions")
	local action_state = require("telescope.actions.state")
	local conf = require("telescope.config").values
	local previewers = require("telescope.previewers")

	pickers
		.new({}, {
			prompt_title = "pi-remarks",
			finder = remark_finder(finders),
			sorter = conf.generic_sorter({}),
			previewer = remark_previewer(previewers),
			attach_mappings = function(prompt_bufnr, map)
				local refresh = function()
					local current_picker = action_state.get_current_picker(prompt_bufnr)
					current_picker:refresh(remark_finder(finders), { reset_prompt = true })
				end
				map({ "i", "n" }, "<CR>", function()
					local entry = action_state.get_selected_entry()
					if not entry then
						return
					end
					actions.close(prompt_bufnr)
					jump(entry.value.remark)
				end)
				map({ "i", "n" }, "<C-d>", function()
					local entry = action_state.get_selected_entry()
					if not entry then
						return
					end
					store.remove_index(entry.value.index)
					refresh()
				end)
				map({ "i", "n" }, "<C-e>", function()
					local entry = action_state.get_selected_entry()
					if not entry then
						return
					end
					local target = entry.value.remark
					popup.open({
						initial = target.comment,
						on_confirm = function(comment)
							if not comment then
								return
							end
							target.comment = comment
							refresh()
						end,
					})
				end)
				map({ "i", "n" }, "<C-x>", function()
					local remarks = store.all()
					if #remarks == 0 then
						return
					end
					vim.ui.select({ false, true }, {
						prompt = ("очистить все замечания (%d)?"):format(#remarks),
						format_item = function(choice)
							return choice and "да" or "нет"
						end,
					}, function(confirmed)
						if not confirmed then
							return
						end
						store.clear()
						actions.close(prompt_bufnr)
					end)
				end)
				map({ "i", "n" }, "<C-s>", function()
					actions.close(prompt_bufnr)
					require("pi-remarks").send()
				end)
				return true
			end,
		})
		:find()
end

local function select_remarks()
	local items = {}
	for index, remark in ipairs(store.all()) do
		items[index] = { remark = remark }
	end
	vim.ui.select(items, {
		prompt = "pi-remarks",
		format_item = function(item)
			return M.remark_entry_with_preview(item.remark)
		end,
	}, function(choice)
		if choice then
			jump(choice.remark)
		end
	end)
end

function M.remarks()
	if #store.all() == 0 then
		vim.notify("pi-remarks: замечаний нет", vim.log.levels.WARN)
		return
	end
	if telescope_available() then
		telescope_remarks()
	else
		select_remarks()
	end
end

local function telescope_agent(agents, root, on_selected)
	local pickers = require("telescope.pickers")
	local finders = require("telescope.finders")
	local actions = require("telescope.actions")
	local action_state = require("telescope.actions.state")
	local conf = require("telescope.config").values

	local finished = false
	local function finish(agent)
		if finished then
			return
		end
		finished = true
		on_selected(agent and agent.pane_id or nil)
	end

	pickers
		.new({}, {
			prompt_title = "pi-remarks: агент",
			finder = finders.new_table({
				results = agents,
				entry_maker = function(agent)
					return {
						value = agent,
						display = function()
							return M.agent_entry(agent)
						end,
						ordinal = M.agent_entry(agent),
					}
				end,
			}),
			sorter = conf.generic_sorter({}),
			attach_mappings = function(prompt_bufnr, map)
				map({ "i", "n" }, "<CR>", function()
					local entry = action_state.get_selected_entry()
					actions.close(prompt_bufnr)
					finish(entry and entry.value or nil)
				end)
				vim.api.nvim_create_autocmd("BufWipeout", {
					buffer = prompt_bufnr,
					callback = function()
						finish(nil)
					end,
				})
				return true
			end,
		})
		:find()
end

function M.agent(agents, root, on_selected)
	local sorted = M.sort_agents(agents, root)
	if telescope_available() then
		telescope_agent(sorted, root, on_selected)
		return
	end
	vim.ui.select(sorted, {
		prompt = "pi-remarks: выберите агента",
		format_item = M.agent_entry,
	}, function(choice)
		on_selected(choice and choice.pane_id or nil)
	end)
end

return M

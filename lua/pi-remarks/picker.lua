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

local function jump(remark)
	local file_bufnr = vim.fn.bufnr(remark.path)
	local wins = file_bufnr > 0 and vim.fn.win_findbuf(file_bufnr) or {}
	if wins[1] then
		vim.api.nvim_set_current_win(wins[1])
	else
		vim.cmd.split(vim.fn.fnameescape(remark.path))
	end
	vim.api.nvim_win_set_cursor(0, { remark.line_start, 0 })
end

local function remark_results(root)
	local results = {}
	for index, remark in ipairs(store.load(root)) do
		results[index] = { index = index, remark = remark }
	end
	return results
end

local function remark_finder(finder, root)
	return finder.new_table({
		results = remark_results(root),
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

local function telescope_remarks(root)
	local pickers = require("telescope.pickers")
	local finders = require("telescope.finders")
	local actions = require("telescope.actions")
	local action_state = require("telescope.actions.state")
	local conf = require("telescope.config").values
	local previewers = require("telescope.previewers")

	pickers
		.new({}, {
			prompt_title = "pi-remarks",
			finder = remark_finder(finders, root),
			sorter = conf.generic_sorter({}),
			previewer = remark_previewer(previewers),
			attach_mappings = function(prompt_bufnr, map)
				local refresh = function()
					local current_picker = action_state.get_current_picker(prompt_bufnr)
					current_picker:refresh(remark_finder(finders, root), { reset_prompt = true })
				end
				map({ "i", "n" }, "<CR>", function()
					local entry = action_state.get_selected_entry()
					actions.close(prompt_bufnr)
					jump(entry.value.remark)
				end)
				map({ "i", "n" }, "<C-d>", function()
					local entry = action_state.get_selected_entry()
					local remarks = store.load(root)
					table.remove(remarks, entry.value.index)
					store.save(root, remarks)
					refresh()
				end)
				map({ "i", "n" }, "<C-e>", function()
					local entry = action_state.get_selected_entry()
					popup.open({
						initial = entry.value.remark.comment,
						on_confirm = function(comment)
							if not comment then
								return
							end
							local remarks = store.load(root)
							local current = remarks[entry.value.index]
							if not current then
								return
							end
							current.comment = comment
							store.save(root, remarks)
							refresh()
						end,
					})
				end)
				map({ "i", "n" }, "<C-s>", function()
					actions.close(prompt_bufnr)
					require("pi-remarks").send(root)
				end)
				return true
			end,
		})
		:find()
end

local function select_remarks(root)
	local remarks = store.load(root)
	local items = {}
	for index, remark in ipairs(remarks) do
		items[index] = { index = index, remark = remark }
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

function M.remarks(root)
	if #store.load(root) == 0 then
		vim.notify("pi-remarks: замечаний нет", vim.log.levels.WARN)
		return
	end
	if telescope_available() then
		telescope_remarks(root)
	else
		select_remarks(root)
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
				results = M.sort_agents(agents, root),
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

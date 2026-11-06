local block = require("nrdr.block")
local picker = require("nrdr.picker")
local store = require("nrdr.store")

local function disable_telescope()
	local saved = package.loaded["telescope.pickers"]
	package.loaded["telescope.pickers"] = false
	return function()
		if saved == nil then
			package.loaded["telescope.pickers"] = nil
		else
			package.loaded["telescope.pickers"] = saved
		end
	end
end

describe("remark entry", function()
	it("renders a single line when start equals end", function()
		assert.same(
			"src/a.lua:3",
			picker.remark_entry({ relpath = "src/a.lua", line_start = 3, line_end = 3, comment = "x" })
		)
	end)

	it("renders a range when start differs from end", function()
		assert.same(
			"src/a.lua:3-7",
			picker.remark_entry({ relpath = "src/a.lua", line_start = 3, line_end = 7, comment = "x" })
		)
	end)

	it("appends the first comment line for the select fallback", function()
		local entry = picker.remark_entry_with_preview({
			relpath = "a.lua",
			line_start = 2,
			line_end = 2,
			comment = "первая\nвторая",
		})
		assert.same("a.lua:2 первая", entry)
	end)
end)

describe("agent entry", function()
	it("uses the name field when present", function()
		local entry = picker.agent_entry({
			name = "reviewer",
			terminal_title_stripped = "ignored",
			cwd = "/tmp/proj",
			agent_status = "idle",
			pane_id = "w1:p1",
		})
		assert.same("reviewer · /tmp/proj · idle · w1:p1", entry)
	end)

	it("falls back to the stripped terminal title", function()
		local entry = picker.agent_entry({
			terminal_title_stripped = "π - nvim",
			cwd = "/tmp/proj",
			agent_status = "working",
			pane_id = "w2:p2",
		})
		assert.same("π - nvim · /tmp/proj · working · w2:p2", entry)
	end)

	it("uses a placeholder without name and title", function()
		local entry = picker.agent_entry({ cwd = "/tmp/proj", agent_status = "idle", pane_id = "w3:p3" })
		assert.same("? · /tmp/proj · idle · w3:p3", entry)
	end)
end)

describe("sort_agents", function()
	local match = { pane_id = "p-match", cwd = "/tmp/proj" }
	local other_one = { pane_id = "p-other-1", cwd = "/elsewhere" }
	local other_two = { pane_id = "p-other-2", cwd = "/elsewhere-two" }

	it("puts agents matching the cwd first and keeps the rest in order", function()
		local sorted = picker.sort_agents({ other_one, match, other_two }, "/tmp/proj")
		assert.same({ match, other_one, other_two }, sorted)
	end)

	it("keeps the original order when no agent matches", function()
		local sorted = picker.sort_agents({ other_two, other_one }, "/tmp/proj")
		assert.same({ other_two, other_one }, sorted)
	end)
end)

describe("remarks picker", function()
	local original_notify
	local notifications
	local original_select
	local select_calls
	local remark_one
	local remark_two
	local restore_telescope
	local tmp_file

	local function telescope_stub(selected_entry)
		local saved = {}
		for _, name in ipairs({
			"telescope.pickers",
			"telescope.finders",
			"telescope.config",
			"telescope.actions",
			"telescope.actions.state",
			"telescope.previewers",
		}) do
			saved[name] = package.loaded[name]
		end
		local captured = { mappings = {}, refreshes = 0, closes = 0 }
		local prompt_bufnr = vim.api.nvim_create_buf(false, true)
		captured.prompt_bufnr = prompt_bufnr
		package.loaded["telescope.finders"] = {
			new_table = function(options)
				captured.last_finder = options
				return options
			end,
		}
		package.loaded["telescope.pickers"] = {
			new = function(_, options)
				return {
					find = function()
						options.attach_mappings(prompt_bufnr, function(modes, key, callback)
							for _, mode in ipairs(modes) do
								captured.mappings[mode .. ":" .. key] = callback
							end
						end)
					end,
				}
			end,
		}
		package.loaded["telescope.actions.state"] = {
			get_current_picker = function()
				return {
					refresh = function(_, finder)
						captured.refreshes = captured.refreshes + 1
						captured.last_finder = finder.finder_options or finder
					end,
				}
			end,
			get_selected_entry = function()
				return selected_entry
			end,
		}
		package.loaded["telescope.actions"] = {
			close = function()
				captured.closes = captured.closes + 1
			end,
		}
		package.loaded["telescope.config"] = {
			values = {
				generic_sorter = function()
					return {}
				end,
			},
		}
		package.loaded["telescope.previewers"] = {
			new_buffer_previewer = function(options)
				captured.preview_options = options
				return options
			end,
		}
		return captured,
			function()
				pcall(vim.api.nvim_buf_delete, prompt_bufnr, { force = true })
				for name, value in pairs(saved) do
					package.loaded[name] = value
				end
			end
	end

	before_each(function()
		remark_one = {
			path = "/tmp/proj/a.lua",
			relpath = "a.lua",
			line_start = 1,
			line_end = 1,
			comment = "первое\nрасшифровка",
		}
		remark_two = {
			path = "/tmp/proj/b.go",
			relpath = "b.go",
			line_start = 4,
			line_end = 9,
			comment = "второе",
		}
		store.add(remark_one)
		store.add(remark_two)
		original_notify = vim.notify
		notifications = {}
		vim.notify = function(message, level)
			table.insert(notifications, { message = message, level = level })
		end
		original_select = vim.ui.select
		select_calls = {}
		vim.ui.select = function(items, opts, on_choice)
			table.insert(select_calls, { items = items, opts = opts, on_choice = on_choice })
		end
	end)

	after_each(function()
		if restore_telescope then
			restore_telescope()
			restore_telescope = nil
		end
		vim.notify = original_notify
		vim.ui.select = original_select
		store.clear()
		if tmp_file then
			if vim.fn.bufnr(tmp_file) > 0 then
				pcall(vim.api.nvim_buf_delete, vim.fn.bufnr(tmp_file), { force = true })
			end
			vim.fn.delete(tmp_file)
			tmp_file = nil
		end
	end)

	it("opens telescope with entries and deletes through <C-d> with refresh", function()
		local captured, restore = telescope_stub({ value = { index = 1, remark = remark_one } })
		restore_telescope = restore
		picker.remarks()

		local results = captured.last_finder.results
		assert.same(2, #results)
		assert.same(1, results[1].index)
		assert.same("a.lua:1", captured.last_finder.entry_maker(results[1]).display())

		assert.truthy(captured.mappings["i:<CR>"])
		assert.truthy(captured.mappings["n:<CR>"])
		assert.truthy(captured.mappings["i:<C-d>"])
		assert.truthy(captured.mappings["i:<C-e>"])
		assert.truthy(captured.mappings["i:<C-x>"])
		assert.truthy(captured.mappings["i:<C-s>"])

		captured.mappings["n:<C-d>"]()

		local remarks = store.all()
		assert.same(1, #remarks)
		assert.same("b.go", remarks[1].relpath)
		assert.same(1, captured.refreshes)
		assert.same(1, #captured.last_finder.results)
		assert.same("b.go:4-9", captured.last_finder.entry_maker(captured.last_finder.results[1]).display())
	end)

	it("edits the comment through <C-e> and the popup", function()
		local captured, restore = telescope_stub({ value = { index = 1, remark = remark_one } })
		restore_telescope = restore
		picker.remarks()

		captured.mappings["n:<C-e>"]()
		assert.same({ "первое", "расшифровка" }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
		vim.api.nvim_buf_set_lines(0, 0, -1, false, { "исправлено" })
		vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("ZZ", true, false, true), "mx", false)

		local remarks = store.all()
		assert.same("исправлено", remarks[1].comment)
		assert.same(1, captured.refreshes)
	end)

	it("edits exactly the captured remark when indices shift during the popup", function()
		local captured, restore = telescope_stub({ value = { index = 1, remark = remark_one } })
		picker.remarks()

		store.remove_index(1)

		captured.mappings["n:<C-e>"]()
		assert.same({ "первое", "расшифровка" }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
		vim.api.nvim_buf_set_lines(0, 0, -1, false, { "правка поверх сдвига" })
		vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("ZZ", true, false, true), "mx", false)

		local remarks = store.all()
		assert.same(1, #remarks)
		assert.same("второе", remarks[1].comment)
		assert.same("правка поверх сдвига", remark_one.comment)
	end)

	it("previews the remark block with the diff filetype", function()
		local with_diff = {
			path = "/tmp/proj/a.lua",
			relpath = "a.lua",
			line_start = 1,
			line_end = 1,
			comment = "первое\nрасшифровка",
			diff = {
				header = "@@ -1 +1 @@",
				body = { " context", "-old", "+new" },
			},
		}
		store.clear()
		store.add(with_diff)
		local captured, restore = telescope_stub({ value = { index = 1, remark = with_diff } })
		picker.remarks()

		local target = vim.api.nvim_create_buf(false, true)
		captured.preview_options.define_preview(
			{ state = { bufnr = target } },
			{ value = { index = 1, remark = with_diff } }
		)

		assert.same(vim.split(block.remark_block(with_diff), "\n"), vim.api.nvim_buf_get_lines(target, 0, -1, false))
		assert.same("diff", vim.bo[target].filetype)
		vim.api.nvim_buf_delete(target, { force = true })
	end)

	it("edits the comment through <C-e> and keeps the diff snapshot", function()
		local with_diff = {
			path = "/tmp/proj/a.lua",
			relpath = "a.lua",
			line_start = 1,
			line_end = 1,
			comment = "первое\nрасшифровка",
			diff = {
				header = "@@ -1 +1 @@",
				body = { " context", "-old", "+new" },
			},
		}
		store.clear()
		store.add(with_diff)
		local captured, restore = telescope_stub({ value = { index = 1, remark = with_diff } })
		picker.remarks()

		captured.mappings["n:<C-e>"]()
		assert.same({ "первое", "расшифровка" }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
		vim.api.nvim_buf_set_lines(0, 0, -1, false, { "исправлено" })
		vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("ZZ", true, false, true), "mx", false)

		local remarks = store.all()
		assert.same("исправлено", remarks[1].comment)
		assert.same(with_diff.diff, remarks[1].diff)
	end)

	it("sends remarks through <C-s> by asking for an agent", function()
		local captured, restore = telescope_stub({ value = { index = 1, remark = remark_one } })
		restore_telescope = restore
		local original_system = vim.system
		vim.system = function(argv)
			return {
				wait = function()
					if argv[3] == "list" then
						return {
							code = 0,
							stdout = vim.json.encode({
								result = { agents = { { pane_id = "p1", agent_status = "idle", cwd = "/tmp" } } },
							}),
							stderr = "",
						}
					end
					return { code = 0, stdout = "", stderr = "" }
				end,
			}
		end
		picker.remarks()

		restore()
		restore_telescope = disable_telescope()

		captured.mappings["n:<C-s>"]()
		assert.same(1, #select_calls)
		assert.same("nrdr: выберите агента", select_calls[1].opts.prompt)
		vim.system = original_system
	end)

	it("ignores actions on an empty selection without mutations", function()
		local captured, restore = telescope_stub(nil)
		restore_telescope = restore
		picker.remarks()
		local buf_before = vim.api.nvim_get_current_buf()
		local wins_before = #vim.api.nvim_list_wins()

		captured.mappings["n:<CR>"]()
		captured.mappings["n:<C-d>"]()
		captured.mappings["n:<C-e>"]()

		assert.same(2, #store.all())
		assert.same(0, captured.refreshes)
		assert.same(0, captured.closes)
		assert.same(buf_before, vim.api.nvim_get_current_buf())
		assert.same(wins_before, #vim.api.nvim_list_wins())
	end)

	it("clears the stack and closes the picker through <C-x> on confirm", function()
		local captured, restore = telescope_stub({ value = { index = 1, remark = remark_one } })
		restore_telescope = restore
		picker.remarks()

		captured.mappings["n:<C-x>"]()

		assert.same(1, #select_calls)
		assert.same(2, #select_calls[1].items)
		select_calls[1].on_choice(true)

		assert.same({}, store.all())
		assert.same(1, captured.closes)
	end)

	it("keeps the stack through <C-x> on decline", function()
		local captured, restore = telescope_stub({ value = { index = 1, remark = remark_one } })
		restore_telescope = restore
		picker.remarks()

		captured.mappings["n:<C-x>"]()
		select_calls[1].on_choice(false)

		assert.same(2, #store.all())
		assert.same(0, captured.closes)
	end)

	it("does not open confirm on an emptied picker through <C-x>", function()
		store.clear()
		store.add(remark_one)
		local captured, restore = telescope_stub({ value = { index = 1, remark = remark_one } })
		restore_telescope = restore
		picker.remarks()

		captured.mappings["n:<C-d>"]()
		assert.same({}, store.all())

		captured.mappings["n:<C-x>"]()

		assert.same(0, #select_calls)
	end)

	it("jumps through :edit when the file buffer is not open", function()
		restore_telescope = disable_telescope()
		local file = "/tmp/nrdr-jump-target.lua"
		vim.fn.writefile({ "line one", "line two" }, file)
		tmp_file = file
		store.clear()
		store.add({ path = file, relpath = "jump-target.lua", line_start = 2, line_end = 2, comment = "c" })
		local wins_before = #vim.api.nvim_list_wins()

		picker.remarks()
		select_calls[1].on_choice(select_calls[1].items[1])

		assert.same(wins_before, #vim.api.nvim_list_wins())
		assert.same(file, vim.api.nvim_buf_get_name(0))
		assert.same(2, vim.api.nvim_win_get_cursor(0)[1])
	end)

	it("clamps the cursor line when the file is shorter than the remark line", function()
		restore_telescope = disable_telescope()
		local file = "/tmp/nrdr-short-target.lua"
		vim.fn.writefile({ "only line", "second line" }, file)
		tmp_file = file
		store.clear()
		store.add({ path = file, relpath = "short.lua", line_start = 10, line_end = 10, comment = "c" })

		picker.remarks()
		select_calls[1].on_choice(select_calls[1].items[1])

		assert.same(file, vim.api.nvim_buf_get_name(0))
		assert.same(2, vim.api.nvim_win_get_cursor(0)[1])
	end)

	it("clamps the cursor when the remark points past an open deleted buffer", function()
		restore_telescope = disable_telescope()
		local file = "/tmp/nrdr-deleted-target.lua"
		vim.fn.writefile({ "line one", "line two" }, file)
		vim.cmd.edit(vim.fn.fnameescape(file))
		os.remove(file)
		store.clear()
		store.add({ path = file, relpath = "deleted.lua", line_start = 10, line_end = 10, comment = "c" })
		local win_before = vim.api.nvim_get_current_win()
		local wins_before = #vim.api.nvim_list_wins()

		picker.remarks()
		select_calls[1].on_choice(select_calls[1].items[1])

		assert.same(win_before, vim.api.nvim_get_current_win())
		assert.same(wins_before, #vim.api.nvim_list_wins())
		assert.same(2, vim.api.nvim_win_get_cursor(win_before)[1])
	end)

	it("warns and does nothing when the remark file is missing", function()
		restore_telescope = disable_telescope()
		local missing = "/tmp/nrdr-missing-target.lua"
		os.remove(missing)
		store.clear()
		store.add({ path = missing, relpath = "missing.lua", line_start = 3, line_end = 3, comment = "c" })
		local wins_before = #vim.api.nvim_list_wins()
		local buf_before = vim.api.nvim_get_current_buf()

		picker.remarks()
		select_calls[1].on_choice(select_calls[1].items[1])

		local warned = false
		for _, call in ipairs(notifications) do
			if
				call.level == vim.log.levels.WARN
				and call.message:find("файл замечания не существует: missing.lua", 1, true)
			then
				warned = true
			end
		end
		assert.truthy(warned)
		assert.same(buf_before, vim.api.nvim_get_current_buf())
		assert.same(wins_before, #vim.api.nvim_list_wins())
		assert.same(1, #store.all())
	end)

	it("warns on an empty stack", function()
		store.clear()
		picker.remarks()
		assert.same(0, #select_calls)
		assert.same(1, #notifications)
		assert.same(vim.log.levels.WARN, notifications[1].level)
	end)
end)

describe("agent picker", function()
	local cwd
	local original_select
	local select_calls
	local match
	local other_one
	local other_two
	local restore_telescope

	local function telescope_agent_stub(selected_entry)
		local saved = {}
		for _, name in ipairs({
			"telescope.pickers",
			"telescope.finders",
			"telescope.config",
			"telescope.actions",
			"telescope.actions.state",
		}) do
			saved[name] = package.loaded[name]
		end
		local captured = { mappings = {} }
		local prompt_bufnr = vim.api.nvim_create_buf(false, true)
		captured.prompt_bufnr = prompt_bufnr
		package.loaded["telescope.finders"] = {
			new_table = function(options)
				captured.last_finder = options
				return options
			end,
		}
		package.loaded["telescope.pickers"] = {
			new = function(_, options)
				return {
					find = function()
						options.attach_mappings(prompt_bufnr, function(modes, key, callback)
							for _, mode in ipairs(modes) do
								captured.mappings[mode .. ":" .. key] = callback
							end
						end)
					end,
				}
			end,
		}
		package.loaded["telescope.actions.state"] = {
			get_selected_entry = function()
				return selected_entry
			end,
		}
		package.loaded["telescope.actions"] = {
			close = function() end,
		}
		package.loaded["telescope.config"] = {
			values = {
				generic_sorter = function()
					return {}
				end,
			},
		}
		return captured,
			function()
				pcall(vim.api.nvim_buf_delete, prompt_bufnr, { force = true })
				for name, value in pairs(saved) do
					package.loaded[name] = value
				end
			end
	end

	before_each(function()
		cwd = vim.fs.normalize(vim.fn.getcwd())
		match = { pane_id = "p-match", cwd = cwd, name = "reviewer", agent_status = "idle" }
		other_one =
			{ pane_id = "p-other-1", cwd = "/elsewhere", terminal_title_stripped = "π - x", agent_status = "working" }
		other_two = { pane_id = "p-other-2", cwd = "/elsewhere-two", agent_status = "idle" }
		original_select = vim.ui.select
		select_calls = {}
		vim.ui.select = function(items, opts, on_choice)
			table.insert(select_calls, { items = items, opts = opts, on_choice = on_choice })
		end
	end)

	after_each(function()
		if restore_telescope then
			restore_telescope()
			restore_telescope = nil
		end
		vim.ui.select = original_select
	end)

	it("opens telescope with cwd-first sorted entries and delivers the selected pane", function()
		local chosen
		local captured, restore = telescope_agent_stub({ value = other_one })
		restore_telescope = restore
		picker.agent({ other_one, match, other_two }, cwd, function(pane_id)
			chosen = pane_id
		end)

		assert.same({ match, other_one, other_two }, captured.last_finder.results)
		assert.same("reviewer · " .. cwd .. " · idle · p-match", captured.last_finder.entry_maker(match).display())
		assert.same(
			"π - x · /elsewhere · working · p-other-1",
			captured.last_finder.entry_maker(other_one).display()
		)
		assert.truthy(captured.mappings["i:<CR>"])

		captured.mappings["n:<CR>"]()
		assert.same("p-other-1", chosen)
	end)

	it("asks through ui.select without telescope and delivers the chosen pane", function()
		restore_telescope = disable_telescope()
		local chosen
		picker.agent({ other_one, match }, cwd, function(pane_id)
			chosen = pane_id
		end)

		assert.same(1, #select_calls)
		assert.same({ match, other_one }, select_calls[1].items)
		assert.same(
			"reviewer · " .. cwd .. " · idle · p-match",
			select_calls[1].opts.format_item(select_calls[1].items[1])
		)
		select_calls[1].on_choice(select_calls[1].items[2])
		assert.same("p-other-1", chosen)
	end)

	it("delivers nothing when the agent picker is cancelled", function()
		restore_telescope = disable_telescope()
		local chosen = "sentinel"
		picker.agent({ match }, cwd, function(pane_id)
			chosen = pane_id
		end)
		select_calls[1].on_choice(nil)
		assert.is_nil(chosen)
	end)
end)

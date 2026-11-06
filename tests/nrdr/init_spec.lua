local diff = require("nrdr.diff")
local pi = require("nrdr")
local store = require("nrdr.store")

describe("send deliver pipeline", function()
	local cwd
	local pane
	local pane_counter = 0
	local original_system
	local real_vim_system
	local original_notify
	local original_select
	local spawns
	local notifications
	local select_calls
	local telescope_path
	local had_telescope

	local function remark(name, comment)
		return {
			path = "/tmp/proj/" .. name,
			relpath = name,
			line_start = 1,
			line_end = 1,
			comment = comment,
		}
	end

	local function spawns_of(kind)
		return vim.tbl_filter(function(spawn)
			return spawn.argv[3] == kind
		end, spawns)
	end

	local function prompt_exit(code)
		local prompt_spawns = spawns_of("prompt")
		prompt_spawns[#prompt_spawns].on_exit({ code = code, stdout = "", stderr = code == 0 and "" or "boom\n" })
	end

	local function wait_exit(code)
		local wait_spawns = spawns_of("wait")
		wait_spawns[#wait_spawns].on_exit({ code = code, stdout = "", stderr = code == 0 and "" or "timeout\n" })
	end

	local function find_notification(level, pattern)
		for _, call in ipairs(notifications) do
			if call.level == level and call.message:find(pattern, 1, true) then
				return call.message
			end
		end
		return nil
	end

	local function wait_for_notification(level, pattern)
		vim.wait(1000, function()
			return find_notification(level, pattern) ~= nil
		end, 20)
	end

	local function pump()
		vim.wait(150, function()
			return false
		end, 10)
	end

	before_each(function()
		real_vim_system = vim.system
		cwd = vim.fs.normalize(vim.fn.getcwd())
		pane_counter = pane_counter + 1
		pane = "pane-" .. tostring(pane_counter)
		spawns = {}
		notifications = {}
		select_calls = {}
		original_system = vim.system
		vim.system = function(argv, _, on_exit)
			local spawn = { argv = argv, on_exit = on_exit, killed = false }
			table.insert(spawns, spawn)
			return {
				pid = 42424,
				kill = function(_, signal)
					spawn.killed = true
					spawn.kill_signal = signal
					return true
				end,
				wait = function()
					if argv[3] == "list" then
						return {
							code = 0,
							stdout = vim.json.encode({
								result = {
									agents = {
										{ pane_id = pane, agent_status = "idle", cwd = cwd },
										{ pane_id = "p-other", agent_status = "working", cwd = "/elsewhere" },
									},
								},
							}),
							stderr = "",
						}
					end
					return { code = 0, stdout = "", stderr = "" }
				end,
			}
		end
		original_notify = vim.notify
		vim.notify = function(message, level)
			table.insert(notifications, { message = message, level = level })
		end
		original_select = vim.ui.select
		vim.ui.select = function(items, opts, on_choice)
			table.insert(select_calls, { items = items, opts = opts, on_choice = on_choice })
			on_choice(items[1], 1)
		end
		telescope_path = vim.fs.normalize(vim.fn.stdpath("data") .. "/lazy/telescope.nvim")
		had_telescope = vim.list_contains(vim.opt.runtimepath:get(), telescope_path)
		if had_telescope then
			vim.opt.runtimepath:remove(telescope_path)
		end
		pi.setup({})
	end)

	after_each(function()
		vim.system = original_system
		vim.notify = original_notify
		vim.ui.select = original_select
		if had_telescope then
			vim.opt.runtimepath:append(telescope_path)
		end
		store.clear()
	end)

	it("removes sent remarks and starts the working→idle wait chain after a successful prompt", function()
		store.add(remark("a.lua", "первое"))
		store.add(remark("b.go", "второе"))

		pi.send()

		assert.same(1, #select_calls)
		assert.same(
			{ pane, "p-other" },
			vim.tbl_map(function(agent)
				return agent.pane_id
			end, select_calls[1].items)
		)
		assert.same(2, #store.all())
		assert.same(0, #spawns_of("wait"))

		prompt_exit(0)
		pump()
		wait_for_notification(vim.log.levels.INFO, "отправлено (pane " .. pane .. ")")

		assert.same({}, store.all())
		assert.same(1, #spawns_of("wait"))
		assert.same(
			{ "herdr", "agent", "wait", pane, "--until", "working", "--timeout", "15000" },
			spawns_of("wait")[1].argv
		)

		wait_exit(0)
		pump()

		assert.same(2, #spawns_of("wait"))
		assert.same(
			{ "herdr", "agent", "wait", pane, "--until", "idle", "--timeout", "600000" },
			spawns_of("wait")[2].argv
		)

		wait_exit(0)
		wait_for_notification(vim.log.levels.INFO, "агент завершил ход")
	end)

	it("keeps remarks when the prompt fails", function()
		store.add(remark("a.lua", "первое"))

		pi.send()
		prompt_exit(1)
		wait_for_notification(vim.log.levels.ERROR, "завершился с ошибкой")

		local remarks = store.all()
		assert.same(1, #remarks)
		assert.same("первое", remarks[1].comment)
		assert.same(0, #spawns_of("wait"))
		assert.truthy(find_notification(vim.log.levels.ERROR, "boom"))
	end)

	it("preserves remarks added while the prompt is in flight and removes sent ones", function()
		store.add(remark("a.lua", "первое"))

		pi.send()

		store.add(remark("b.go", "добавлено в полёте"))

		prompt_exit(0)
		pump()
		wait_for_notification(vim.log.levels.INFO, "отправлено (pane " .. pane .. ")")

		local remarks = store.all()
		assert.same(1, #remarks)
		assert.same("добавлено в полёте", remarks[1].comment)

		wait_exit(0)
		pump()
		wait_exit(0)
		wait_for_notification(vim.log.levels.INFO, "агент завершил ход")
	end)

	it("does not spawn another prompt when the stack is empty", function()
		local prompts_before = #spawns_of("prompt")

		pi.send()

		assert.same(prompts_before, #spawns_of("prompt"))
		assert.same(0, #select_calls)
		assert.truthy(find_notification(vim.log.levels.ERROR, "замечаний нет"))
	end)

	it("always asks for the agent on every send", function()
		store.add(remark("a.lua", "первое"))

		pi.send()
		prompt_exit(0)
		pump()
		wait_for_notification(vim.log.levels.INFO, "отправлено (pane " .. pane .. ")")
		wait_exit(0)
		pump()
		wait_for_notification(vim.log.levels.INFO, "агент завершил ход")
		assert.same(1, #select_calls)

		store.add(remark("b.go", "второе"))
		pi.send()

		assert.same(2, #select_calls)
	end)

	it("does not spawn a second waiter while the chain is alive", function()
		store.add(remark("a.lua", "первое"))

		pi.send()
		prompt_exit(0)
		pump()
		wait_for_notification(vim.log.levels.INFO, "отправлено (pane " .. pane .. ")")
		assert.same(1, #spawns_of("wait"))

		store.add(remark("b.go", "второе"))

		pi.send()
		prompt_exit(0)
		pump()
		wait_for_notification(vim.log.levels.INFO, "отправлено (pane " .. pane .. ")")

		assert.same(1, #spawns_of("wait"))
		assert.truthy(
			find_notification(vim.log.levels.WARN, "уже ждём завершения хода агента")
		)

		wait_exit(0)
		pump()
		wait_exit(0)
		wait_for_notification(vim.log.levels.INFO, "агент завершил ход")
	end)

	it("warns and releases the slot when the turn never starts", function()
		store.add(remark("a.lua", "первое"))

		pi.send()
		prompt_exit(0)
		pump()
		wait_for_notification(vim.log.levels.INFO, "отправлено (pane " .. pane .. ")")
		assert.same(
			{ "herdr", "agent", "wait", pane, "--until", "working", "--timeout", "15000" },
			spawns_of("wait")[1].argv
		)

		wait_exit(1)
		pump()
		wait_for_notification(vim.log.levels.WARN, "ход агента не начался за 15с")

		assert.same(1, #spawns_of("wait"))
		assert.is_nil(find_notification(vim.log.levels.INFO, "агент завершил ход"))

		store.add(remark("b.go", "второе"))
		pi.send()
		prompt_exit(0)
		pump()
		wait_for_notification(vim.log.levels.INFO, "отправлено (pane " .. pane .. ")")

		assert.same(2, #spawns_of("wait"))
		assert.same("--until", spawns_of("wait")[2].argv[5])
		assert.same("working", spawns_of("wait")[2].argv[6])
	end)

	it("kills the active chain phase on VimLeavePre", function()
		store.add(remark("a.lua", "первое"))

		pi.send()
		prompt_exit(0)
		pump()
		wait_for_notification(vim.log.levels.INFO, "отправлено (pane " .. pane .. ")")
		assert.same(1, #spawns_of("wait"))

		vim.cmd("doautocmd VimLeavePre")

		assert.is_true(spawns_of("wait")[1].killed)
		assert.same("term", spawns_of("wait")[1].kill_signal)
	end)

	it("stores the diff snapshot with add_line in a git repository", function()
		vim.system = real_vim_system
		local repo = vim.fs.normalize(vim.fn.tempname()) .. "-repo"
		vim.fn.mkdir(repo, "p")
		vim.system({ "git", "-C", repo, "init" }, { text = true }):wait()
		local file = repo .. "/src/a.go"
		vim.fn.mkdir(vim.fs.dirname(file), "p")
		vim.fn.writefile({ "line one", "line two" }, file)
		vim.system({ "git", "-C", repo, "add", "src/a.go" }, { text = true }):wait()
		vim.system(
			{ "git", "-C", repo, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-m", "file" },
			{ text = true }
		)
			:wait()
		vim.fn.writefile({ "line one edited", "line two", "line three" }, file)

		local buf = vim.api.nvim_create_buf(false, false)
		vim.api.nvim_buf_set_name(buf, file)
		vim.api.nvim_set_current_buf(buf)
		vim.api.nvim_win_set_cursor(0, { 1, 0 })
		pi.add_line(0)
		vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("iснапшот<Esc>ZZ", true, false, true), "mx", false)

		local remarks = store.all()
		assert.same(1, #remarks)
		assert.same("снапшот", remarks[1].comment)

		local git_diff = vim.system({ "git", "-C", repo, "diff", "-U3", "HEAD", "--", "src/a.go" }, { text = true })
			:wait()
		print("DBG GITDIFF:", git_diff.code, "OUTLEN:", #git_diff.stdout, "ERR:[", git_diff.stderr, "]")
		local expected = diff.match_hunk(git_diff.stdout, 1, 1)
		assert.truthy(expected, "git produced a diff")
		assert.truthy(remarks[1].diff)
		assert.same(expected.header, remarks[1].diff.header)
		assert.same(expected.body, remarks[1].diff.body)
		vim.system = original_system
		vim.fn.delete(repo, "rf")
	end)

	it("refuses adds from the read-only diff pane", function()
		local scratch = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_set_current_buf(scratch)
		vim.bo[scratch].modifiable = false
		vim.wo.diff = true
		local wins_before = #vim.api.nvim_list_wins()

		pi.add_line(0)

		vim.wo.diff = false
		vim.bo[scratch].modifiable = true
		assert.truthy(find_notification(vim.log.levels.WARN, "старая ревизия диффа"))
		assert.same(wins_before, #vim.api.nvim_list_wins())
	end)

	it("refuses adds from the diffview side marked as old", function()
		local scratch = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_set_current_buf(scratch)
		vim.b[scratch].diffview_symbol = "a"
		local wins_before = #vim.api.nvim_list_wins()

		pi.add_line(0)

		assert.truthy(find_notification(vim.log.levels.WARN, "старая ревизия диффа"))
		assert.same(wins_before, #vim.api.nvim_list_wins())
	end)

	it("allows adds from a named nowrite revision buffer", function()
		local file = vim.fs.normalize(vim.fn.tempname()) .. ".lua"
		vim.fn.writefile({ "line one" }, file)
		local buf = vim.api.nvim_create_buf(false, false)
		vim.api.nvim_buf_set_name(buf, file)
		vim.api.nvim_set_current_buf(buf)
		vim.bo[buf].buftype = "nowrite"
		vim.b[buf].diffview_symbol = "b"

		pi.add_line(0)

		vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("iревизия<Esc>ZZ", true, false, true), "mx", false)

		assert.same(1, #store.all())
		assert.truthy(store.all()[1].path:find(file, 1, true))
		store.clear()
		vim.fn.delete(file)
	end)

	it("allows adds from the diffview side marked as new", function()
		local file = vim.fs.normalize(vim.fn.tempname()) .. ".lua"
		vim.fn.writefile({ "line one", "line two" }, file)
		local buf = vim.api.nvim_create_buf(false, false)
		vim.api.nvim_buf_set_name(buf, file)
		vim.api.nvim_set_current_buf(buf)
		vim.b[buf].diffview_symbol = "b"
		vim.wo.diff = true
		local win_before = vim.api.nvim_get_current_win()
		local wins_before = #vim.api.nvim_list_wins()

		pi.add_line(0)

		assert.same(wins_before + 1, #vim.api.nvim_list_wins())
		vim.api.nvim_feedkeys(
			vim.api.nvim_replace_termcodes("iновая сторона<Esc>ZZ", true, false, true),
			"mx",
			false
		)

		assert.same(1, #store.all())
		assert.same("новая сторона", store.all()[1].comment)
		vim.wo[win_before].diff = false
		vim.fn.delete(file)
	end)

	it("refuses adds from a diff side that is not the new one", function()
		local scratch = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_set_current_buf(scratch)
		vim.b[scratch].diffview_symbol = "local"
		local wins_before = #vim.api.nvim_list_wins()

		pi.add_line(0)

		assert.truthy(
			find_notification(
				vim.log.levels.WARN,
				"панель local не является новой стороной диффа"
			)
		)
		assert.same(wins_before, #vim.api.nvim_list_wins())
	end)

	it("does not touch the stack when the agent picker is cancelled", function()
		store.add(remark("a.lua", "первое"))
		local prompts_before = #spawns_of("prompt")
		local waits_before = #spawns_of("wait")
		local original = vim.ui.select
		vim.ui.select = function(_, _, on_choice)
			on_choice(nil)
		end

		pi.send()

		vim.ui.select = original

		assert.same(1, #store.all())
		assert.same("первое", store.all()[1].comment)
		assert.same(prompts_before, #spawns_of("prompt"))
		assert.same(waits_before, #spawns_of("wait"))
	end)
end)

local pi = require("pi-remarks")
local store = require("pi-remarks.store")

describe("send deliver pipeline", function()
	local root
	local pane
	local original_system
	local original_notify
	local original_select
	local spawns
	local notifications
	local select_calls
	local telescope_path
	local had_telescope

	local function remark(name, comment)
		return {
			path = root .. "/" .. name,
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

	before_each(function()
		root = vim.fs.normalize(vim.fn.tempname())
		pane = "pane-" .. vim.fn.sha256(root):sub(1, 8)
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
										{ pane_id = pane, agent_status = "idle", cwd = root },
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
		vim.fn.delete(store.state_path(root))
		vim.fn.delete(root, "rf")
	end)

	it("removes sent remarks and starts the waiter only after a successful prompt", function()
		store.save(root, { remark("a.lua", "первое"), remark("b.go", "второе") })

		pi.send(root)

		assert.same(1, #select_calls)
		assert.same(
			{ pane, "p-other" },
			vim.tbl_map(function(agent)
				return agent.pane_id
			end, select_calls[1].items)
		)
		assert.is_same(2, #store.load(root))
		assert.same(0, #spawns_of("wait"))

		prompt_exit(0)
		wait_for_notification(vim.log.levels.INFO, "отправлено (pane " .. pane .. ")")

		assert.same({}, store.load(root))
		assert.same(1, #spawns_of("wait"))
		assert.same(
			{ "herdr", "agent", "wait", pane, "--until", "idle", "--timeout", "600000" },
			spawns_of("wait")[1].argv
		)

		wait_exit(0)
		wait_for_notification(vim.log.levels.INFO, "агент завершил ход")
	end)

	it("keeps remarks when the prompt fails", function()
		store.save(root, { remark("a.lua", "первое") })

		pi.send(root)
		prompt_exit(1)
		wait_for_notification(vim.log.levels.ERROR, "завершился с ошибкой")

		local remarks = store.load(root)
		assert.same(1, #remarks)
		assert.same("первое", remarks[1].comment)
		assert.is_nil(remarks[1].sent)
		assert.same(0, #spawns_of("wait"))
		assert.truthy(find_notification(vim.log.levels.ERROR, "boom"))
	end)

	it("preserves remarks added while the prompt is in flight and removes sent ones", function()
		store.save(root, { remark("a.lua", "первое") })

		pi.send(root)

		local fresh = store.load(root)
		table.insert(fresh, remark("b.go", "добавлено в полёте"))
		store.save(root, fresh)

		prompt_exit(0)
		wait_for_notification(vim.log.levels.INFO, "отправлено (pane " .. pane .. ")")

		local remarks = store.load(root)
		assert.same(1, #remarks)
		assert.same("добавлено в полёте", remarks[1].comment)
		assert.is_nil(remarks[1].sent)
	end)

	it("does not spawn another prompt when the stack is empty", function()
		store.save(root, {})
		local prompts_before = #spawns_of("prompt")

		pi.send(root)

		assert.same(prompts_before, #spawns_of("prompt"))
		assert.same(0, #select_calls)
		assert.truthy(find_notification(vim.log.levels.ERROR, "замечаний нет"))
	end)

	it("always asks for the agent on every send", function()
		store.save(root, { remark("a.lua", "первое") })

		pi.send(root)
		prompt_exit(0)
		wait_for_notification(vim.log.levels.INFO, "отправлено (pane " .. pane .. ")")
		wait_exit(0)
		wait_for_notification(vim.log.levels.INFO, "агент завершил ход")
		assert.same(1, #select_calls)

		store.save(root, { remark("b.go", "второе") })
		pi.send(root)

		assert.same(2, #select_calls)
	end)

	it("does not spawn a second waiter for the same pane while one is alive", function()
		store.save(root, { remark("a.lua", "первое") })

		pi.send(root)
		prompt_exit(0)
		wait_for_notification(vim.log.levels.INFO, "отправлено (pane " .. pane .. ")")
		assert.same(1, #spawns_of("wait"))

		store.save(root, { remark("b.go", "второе") })

		pi.send(root)
		prompt_exit(0)
		vim.wait(500, function()
			return find_notification(vim.log.levels.WARN, "уже ждём завершения хода агента")
				~= nil
		end, 20)

		assert.same({}, store.load(root))
		assert.same(1, #spawns_of("wait"))
		assert.truthy(
			find_notification(vim.log.levels.WARN, "уже ждём завершения хода агента")
		)

		wait_exit(0)
		wait_for_notification(vim.log.levels.INFO, "агент завершил ход")
	end)

	it("kills the active waiter on VimLeavePre", function()
		store.save(root, { remark("a.lua", "первое") })

		pi.send(root)
		prompt_exit(0)
		wait_for_notification(vim.log.levels.INFO, "отправлено (pane " .. pane .. ")")
		assert.same(1, #spawns_of("wait"))

		vim.cmd("doautocmd VimLeavePre")

		assert.is_true(spawns_of("wait")[1].killed)
		assert.same("term", spawns_of("wait")[1].kill_signal)
	end)
end)

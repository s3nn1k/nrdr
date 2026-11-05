local pi = require("pi-remarks")
local store = require("pi-remarks.store")

describe("send_unsent deliver pipeline", function()
	local root
	local pane
	local original_system
	local original_notify
	local original_select
	local spawns
	local notifications

	local function remark(name, comment)
		return {
			path = root .. "/" .. name,
			relpath = name,
			line_start = 1,
			line_end = 1,
			comment = comment,
			sent = false,
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

	local function wait_for_notification(level, pattern)
		vim.wait(1000, function()
			for _, call in ipairs(notifications) do
				if call.level == level and call.message:find(pattern, 1, true) then
					return true
				end
			end
			return false
		end, 20)
	end

	local function find_notification(level, pattern)
		for _, call in ipairs(notifications) do
			if call.level == level and call.message:find(pattern, 1, true) then
				return call.message
			end
		end
		return nil
	end

	before_each(function()
		root = vim.fs.normalize(vim.fn.tempname())
		pane = "pane-" .. vim.fn.sha256(root):sub(1, 8)
		spawns = {}
		notifications = {}
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
								result = { agents = { { pane_id = pane, agent_status = "idle", cwd = root } } },
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
		vim.ui.select = function(_, _, on_choice)
			on_choice(nil)
		end
		pi.setup({})
	end)

	after_each(function()
		vim.system = original_system
		vim.notify = original_notify
		vim.ui.select = original_select
		vim.fn.delete(store.state_path(root))
		vim.fn.delete(root, "rf")
	end)

	it("marks remarks sent and starts the waiter only after a successful prompt", function()
		store.save(root, { remark("a.lua", "первое"), remark("b.go", "второе") })

		pi.send_unsent(root)

		assert.is_false(store.load(root)[1].sent)
		assert.same(0, #spawns_of("wait"))

		prompt_exit(0)
		wait_for_notification(vim.log.levels.INFO, "отправлено (pane " .. pane .. ")")

		local remarks = store.load(root)
		assert.is_true(remarks[1].sent)
		assert.is_true(remarks[2].sent)
		assert.same(1, #spawns_of("wait"))
		assert.same(
			{ "herdr", "agent", "wait", pane, "--until", "idle", "--timeout", "600000" },
			spawns_of("wait")[1].argv
		)

		wait_exit(0)
		wait_for_notification(vim.log.levels.INFO, "агент завершил ход")
	end)

	it("keeps remarks unsent and skips the waiter when the prompt fails", function()
		store.save(root, { remark("a.lua", "первое") })

		pi.send_unsent(root)
		prompt_exit(1)
		wait_for_notification(vim.log.levels.ERROR, "завершился с ошибкой")

		assert.is_false(store.load(root)[1].sent)
		assert.same(0, #spawns_of("wait"))
		assert.truthy(find_notification(vim.log.levels.ERROR, "boom"))
	end)

	it("preserves remarks added while the prompt is in flight", function()
		store.save(root, { remark("a.lua", "первое") })

		pi.send_unsent(root)

		local fresh = store.load(root)
		table.insert(fresh, remark("b.go", "добавлено в полёте"))
		store.save(root, fresh)

		prompt_exit(0)
		wait_for_notification(vim.log.levels.INFO, "отправлено (pane " .. pane .. ")")

		local remarks = store.load(root)
		assert.same(2, #remarks)
		assert.is_true(remarks[1].sent)
		assert.is_false(remarks[2].sent)
		assert.same("добавлено в полёте", remarks[2].comment)
	end)

	it("does not spawn another prompt when nothing is unsent", function()
		local sent_remark = remark("a.lua", "уже отправлено")
		sent_remark.sent = true
		store.save(root, { sent_remark })
		local prompts_before = #spawns_of("prompt")

		pi.send_unsent(root)

		assert.same(prompts_before, #spawns_of("prompt"))
		assert.truthy(find_notification(vim.log.levels.ERROR, "неотправленных замечаний нет"))
	end)

	it("does not spawn a second waiter for the same pane while one is alive", function()
		store.save(root, { remark("a.lua", "первое") })

		pi.send_unsent(root)
		prompt_exit(0)
		wait_for_notification(vim.log.levels.INFO, "отправлено (pane " .. pane .. ")")
		assert.same(1, #spawns_of("wait"))

		local fresh = store.load(root)
		table.insert(fresh, remark("b.go", "второе"))
		store.save(root, fresh)

		pi.send_unsent(root)
		prompt_exit(0)
		vim.wait(500, function()
			return find_notification(vim.log.levels.WARN, "уже ждём завершения хода агента")
				~= nil
		end, 20)

		assert.is_true(store.load(root)[2].sent)
		assert.same(1, #spawns_of("wait"))
		assert.truthy(
			find_notification(vim.log.levels.WARN, "уже ждём завершения хода агента")
		)

		wait_exit(0)
		wait_for_notification(vim.log.levels.INFO, "агент завершил ход")
	end)

	it("kills the active waiter on VimLeavePre", function()
		store.save(root, { remark("a.lua", "первое") })

		pi.send_unsent(root)
		prompt_exit(0)
		wait_for_notification(vim.log.levels.INFO, "отправлено (pane " .. pane .. ")")
		assert.same(1, #spawns_of("wait"))

		vim.cmd("doautocmd VimLeavePre")

		assert.is_true(spawns_of("wait")[1].killed)
		assert.same("term", spawns_of("wait")[1].kill_signal)
	end)
end)

local M = {}

local function failure_output(done)
	local output = (done.stderr or "") ~= "" and done.stderr or (done.stdout or "")
	return vim.trim(output)
end

function M.build_message(remarks)
	local lines = { ("# Замечания ревью (%d)"):format(#remarks), "" }
	for _, remark in ipairs(remarks) do
		lines[#lines + 1] = ("- %s:%d-%d"):format(remark.relpath, remark.line_start, remark.line_end)
		for _, comment_line in ipairs(vim.split(remark.comment, "\n")) do
			lines[#lines + 1] = "  " .. comment_line
		end
	end
	return table.concat(lines, "\n")
end

local max_error_snippet = 120

local function snippet(text)
	local fragment = vim.trim(text or "")
	if #fragment > max_error_snippet then
		return fragment:sub(1, max_error_snippet - 1) .. "…"
	end
	return fragment
end

function M.parse_agents(json_text)
	local ok, decoded = pcall(vim.json.decode, json_text)
	local agents = ok and type(decoded) == "table" and type(decoded.result) == "table" and decoded.result.agents
	if type(agents) ~= "table" then
		local detail = snippet(ok and json_text or (tostring(decoded) .. ": " .. (json_text or "")))
		return nil, "неожиданный формат ответа herdr agent list: " .. detail
	end
	return agents, nil
end

function M.list_agents(herdr_bin)
	local ok, handle_or_err = pcall(vim.system, { herdr_bin, "agent", "list" }, { text = true })
	if not ok then
		return nil, "не удалось запустить herdr agent list: " .. tostring(handle_or_err)
	end
	local done = handle_or_err:wait()
	if done.code ~= 0 then
		return nil,
			("herdr agent list завершился с ошибкой (code %d): %s"):format(
				done.code,
				failure_output(done)
			)
	end
	return M.parse_agents(done.stdout or "")
end

function M.select_agent(agents, root, on_selected)
	for _, agent in ipairs(agents) do
		if agent.pane_id and vim.fs.normalize(agent.cwd or "") == root then
			on_selected(agent.pane_id)
			return
		end
	end
	vim.ui.select(agents, {
		prompt = "агент с cwd проекта не найден, выберите получателя",
		format_item = function(agent)
			return ("%s (%s)"):format(agent.cwd or "?", agent.agent_status or "?")
		end,
	}, function(_, index)
		if not index then
			on_selected(nil)
			return
		end
		on_selected(agents[index].pane_id)
	end)
end

local function run_async(argv, on_done)
	local label = "herdr agent " .. tostring(argv[3])
	local ok, handle_or_err = pcall(vim.system, argv, { text = true }, function(done)
		local err
		if done.code ~= 0 then
			err = ("%s завершился с ошибкой (code %d): %s"):format(
				label,
				done.code,
				failure_output(done)
			)
		end
		vim.schedule(function()
			on_done(err)
		end)
	end)
	if not ok then
		on_done("не удалось запустить " .. label .. ": " .. tostring(handle_or_err))
		return nil
	end
	return handle_or_err
end

function M.prompt(herdr_bin, pane_id, text, on_done)
	return run_async({ herdr_bin, "agent", "prompt", pane_id, text }, on_done)
end

function M.wait_idle(herdr_bin, pane_id, timeout_ms, on_done)
	return run_async(
		{ herdr_bin, "agent", "wait", pane_id, "--until", "idle", "--timeout", tostring(timeout_ms) },
		on_done
	)
end

return M

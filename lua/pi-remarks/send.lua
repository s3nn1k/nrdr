local block = require("pi-remarks.block")
local util = require("pi-remarks.util")

local M = {}

local function failure_output(done)
	local output = (done.stderr or "") ~= "" and done.stderr or (done.stdout or "")
	return vim.trim(output)
end

function M.build_message(remarks)
	local blocks = {}
	for _, remark in ipairs(remarks) do
		blocks[#blocks + 1] = block.remark_block(remark)
	end
	return table.concat(blocks, "\n\n")
end

function M.parse_agents(json_text)
	local ok, decoded = pcall(vim.json.decode, json_text)
	local agents = ok and type(decoded) == "table" and type(decoded.result) == "table" and decoded.result.agents
	if type(agents) ~= "table" then
		local detail = util.snippet(ok and json_text or (tostring(decoded) .. ": " .. (json_text or "")))
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

function M.wait_for(opts, on_done)
	local argv = { opts.herdr_bin, "agent", "wait", opts.pane_id }
	for _, status in ipairs(opts.statuses) do
		argv[#argv + 1] = "--until"
		argv[#argv + 1] = status
	end
	argv[#argv + 1] = "--timeout"
	argv[#argv + 1] = tostring(opts.timeout_ms)
	return run_async(argv, on_done)
end

return M

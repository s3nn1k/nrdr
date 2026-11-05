local send = require("pi-remarks.send")

local agent_list_fixture = [[
{"result":{"agents":[{"pane_id":"pane-a","agent_status":"idle","cwd":"/tmp/proj-a"},{"pane_id":"pane-b","agent_status":"working","cwd":"/tmp/proj-b"}]}}
]]

local fixture_agents = vim.json.decode(agent_list_fixture).result.agents

describe("build_message", function()
	it("renders the header and indented blocks for several remarks", function()
		local message = send.build_message({
			{
				rel = "src/a.lua",
				line_start = 3,
				line_end = 7,
				comment = "первая строка\nвторая строка",
			},
			{ rel = "b.go", line_start = 1, line_end = 1, comment = "одиночный комментарий" },
		})
		assert.same(
			table.concat({
				"# Замечания ревью (2)",
				"",
				"- src/a.lua:3-7",
				"  первая строка",
				"  вторая строка",
				"- b.go:1-1",
				"  одиночный комментарий",
			}, "\n"),
			message
		)
	end)
end)

describe("parse_agents", function()
	it("extracts agents from a herdr agent list fixture", function()
		local agents, err = send.parse_agents(agent_list_fixture)
		assert.is_nil(err)
		assert.same(2, #agents)
		assert.same("pane-a", agents[1].pane_id)
		assert.same("working", agents[2].agent_status)
	end)

	it("rejects non-json payloads", function()
		local agents, err = send.parse_agents("not json")
		assert.is_nil(agents)
		assert.truthy(err)
	end)

	it("rejects payloads without result.agents", function()
		local agents, err = send.parse_agents("{}")
		assert.is_nil(agents)
		assert.truthy(err)
	end)
end)

describe("list_agents", function()
	local original_system
	local last_argv

	before_each(function()
		original_system = vim.system
		last_argv = nil
		vim.system = function(argv)
			last_argv = argv
			return {
				wait = function()
					return { code = 0, stdout = agent_list_fixture, stderr = "" }
				end,
			}
		end
	end)

	after_each(function()
		vim.system = original_system
	end)

	it("calls herdr agent list and parses the fixture", function()
		local agents, err = send.list_agents("herdr")
		assert.is_nil(err)
		assert.same(2, #agents)
		assert.same({ "herdr", "agent", "list" }, last_argv)
	end)

	it("fails loudly when herdr exits non-zero", function()
		vim.system = function()
			return {
				wait = function()
					return { code = 3, stdout = "", stderr = "boom\n" }
				end,
			}
		end
		local agents, err = send.list_agents("herdr")
		assert.is_nil(agents)
		assert.truthy(err:find("boom", 1, true))
	end)

	it("fails loudly when herdr cannot be spawned", function()
		vim.system = function()
			error("spawn failed: enoent")
		end
		local agents, err = send.list_agents("herdr")
		assert.is_nil(agents)
		assert.truthy(err:find("spawn failed", 1, true))
	end)
end)

describe("select_agent", function()
	local original_select
	local select_calls

	before_each(function()
		original_select = vim.ui.select
		select_calls = {}
		vim.ui.select = function(items, opts, on_choice)
			table.insert(select_calls, { items = items, opts = opts })
			on_choice(items[1], 1)
		end
	end)

	after_each(function()
		vim.ui.select = original_select
	end)

	it("takes the agent whose cwd matches the project root without asking", function()
		local chosen
		send.select_agent(fixture_agents, "/tmp/proj-b", function(pane_id)
			chosen = pane_id
		end)
		assert.same("pane-b", chosen)
		assert.same(0, #select_calls)
	end)

	it("falls back to selecting among all agents when no cwd matches", function()
		local chosen
		send.select_agent(fixture_agents, "/tmp/other", function(pane_id)
			chosen = pane_id
		end)
		assert.same(1, #select_calls)
		assert.same(2, #select_calls[1].items)
		assert.same("pane-a", chosen)
		local label = select_calls[1].opts.format_item(select_calls[1].items[2])
		assert.truthy(label:find("/tmp/proj-b", 1, true))
		assert.truthy(label:find("working", 1, true))
	end)

	it("passes nothing when the fallback is cancelled", function()
		vim.ui.select = function(_, _, on_choice)
			on_choice(nil)
		end
		local chosen = "sentinel"
		send.select_agent(fixture_agents, "/tmp/other", function(pane_id)
			chosen = pane_id
		end)
		assert.is_nil(chosen)
	end)
end)

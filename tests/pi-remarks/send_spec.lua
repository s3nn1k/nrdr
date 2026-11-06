local send = require("pi-remarks.send")

local agent_list_fixture = [[
{"result":{"agents":[{"pane_id":"pane-a","agent_status":"idle","cwd":"/tmp/proj-a"},{"pane_id":"pane-b","agent_status":"working","cwd":"/tmp/proj-b"}]}}
]]

local fixture_agents = vim.json.decode(agent_list_fixture).result.agents

describe("build_message", function()
	it("renders absolute paths and comment blocks separated by blank lines", function()
		local message = send.build_message({
			{
				path = "/abs/src/a.lua",
				line_start = 3,
				line_end = 7,
				comment = "первая строка\nвторая строка",
			},
			{ path = "/abs/b.go", line_start = 1, line_end = 1, comment = "одиночный комментарий" },
		})
		assert.same(
			table.concat({
				"файл: /abs/src/a.lua:3-7",
				"комментарий: первая строка",
				"  вторая строка",
				"",
				"файл: /abs/b.go:1",
				"комментарий: одиночный комментарий",
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

	it("rejects non-json payloads with the decode detail", function()
		local agents, err = send.parse_agents("not json")
		assert.is_nil(agents)
		assert.truthy(err:find("not json", 1, true))
	end)

	it("rejects payloads without result.agents and includes the response fragment", function()
		local agents, err = send.parse_agents("{}")
		assert.is_nil(agents)
		assert.truthy(err:find("{}", 1, true))
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

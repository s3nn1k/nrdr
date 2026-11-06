local store = require("nrdr.store")

describe("store", function()
	local function remark(relpath, comment)
		return { path = "/tmp/proj/" .. relpath, relpath = relpath, line_start = 1, line_end = 1, comment = comment }
	end

	after_each(function()
		store.clear()
	end)

	it("adds remarks into the session stack", function()
		store.add(remark("a.lua", "первое"))
		store.add(remark("b.go", "второе"))
		local remarks = store.all()
		assert.same(2, #remarks)
		assert.same("a.lua", remarks[1].relpath)
		assert.same("второе", remarks[2].comment)
	end)

	it("removes the remark at an index and shifts the rest", function()
		store.add(remark("a.lua", "первое"))
		store.add(remark("b.go", "второе"))
		store.add(remark("c.md", "третье"))
		store.remove_index(2)
		local remarks = store.all()
		assert.same(2, #remarks)
		assert.same("a.lua", remarks[1].relpath)
		assert.same("c.md", remarks[2].relpath)
	end)

	it("keeps only remarks matching the predicate", function()
		store.add(remark("a.lua", "первое"))
		store.add(remark("b.go", "второе"))
		store.add(remark("c.md", "третье"))
		store.keep(function(r)
			return r.relpath ~= "b.go"
		end)
		local remarks = store.all()
		assert.same(2, #remarks)
		assert.same("a.lua", remarks[1].relpath)
		assert.same("c.md", remarks[2].relpath)
	end)

	it("clears the stack", function()
		store.add(remark("a.lua", "первое"))
		store.clear()
		assert.same({}, store.all())
	end)

	it("returns remarks by reference so callers can update them", function()
		store.add(remark("a.lua", "первое"))
		store.all()[1].comment = "исправлено"
		assert.same("исправлено", store.all()[1].comment)
	end)
end)

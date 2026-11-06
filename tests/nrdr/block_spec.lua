local block = require("nrdr.block")

local function remark(options)
	return vim.tbl_extend("force", {
		path = "/abs/src/pay.go",
		relpath = "src/pay.go",
		line_start = 42,
		line_end = 58,
		comment = "первая строка\nвторая строка отступом",
	}, options)
end

describe("remark_block", function()
	it("renders the file line and the comment", function()
		local entry = remark({})
		assert.same(
			table.concat({
				"файл: /abs/src/pay.go:42-58",
				"комментарий: первая строка",
				"  вторая строка отступом",
			}, "\n"),
			block.remark_block(entry)
		)
	end)

	it("renders a single line span", function()
		local entry = remark({ line_start = 42, line_end = 42, comment = "одиночный" })
		assert.same(
			table.concat({ "файл: /abs/src/pay.go:42", "комментарий: одиночный" }, "\n"),
			block.remark_block(entry)
		)
	end)

	it("skips leading and inner empty comment lines", function()
		local entry = remark({ line_start = 3, line_end = 3, comment = "\n\nпервая\n\nвторая\n\n" })
		assert.same(
			table.concat({
				"файл: /abs/src/pay.go:3",
				"комментарий: первая",
				"  вторая",
			}, "\n"),
			block.remark_block(entry)
		)
	end)
end)

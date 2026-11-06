local block = require("pi-remarks.block")

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
	it("renders the file line, the comment and the hunk body without the header", function()
		local entry = remark({
			diff = {
				header = "@@ -36,9 +36,14 @@ func submitOrder(o Order) error {",
				body = {
					" func submitOrder(o Order) error {",
					"-\titems := flatten(o.Groups)",
					"+\titems, err := flatten(o.Groups)",
				},
			},
		})
		assert.same(
			table.concat({
				"файл: /abs/src/pay.go:42-58",
				"комментарий: первая строка",
				"  вторая строка отступом",
				" func submitOrder(o Order) error {",
				"-\titems := flatten(o.Groups)",
				"+\titems, err := flatten(o.Groups)",
			}, "\n"),
			block.remark_block(entry)
		)
	end)

	it("renders a single line span and omits the hunk without a diff", function()
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

local diffview = require("nrdr.diffview")

describe("diffview anchor", function()
	after_each(function()
		package.preload["diffview.lib"] = nil
		package.loaded["diffview.lib"] = nil
		require("nrdr.store").clear()
	end)

	it("resolves the anchor through the lib api for the marked symbol", function()
		local file = vim.fs.normalize(vim.fn.tempname()) .. ".lua"
		local buf = vim.api.nvim_create_buf(false, false)
		vim.api.nvim_buf_set_name(buf, "diffview:///repo/.git/abc123def45/a.lua")
		vim.api.nvim_set_current_buf(buf)
		vim.bo[buf].buftype = "nowrite"
		vim.b[buf].diffview_symbol = "b"
		package.preload["diffview.lib"] = function()
			return {
				get_current_view = function()
					return {
						cur_entry = {
							layout = {
								get_file_for = function(_, symbol)
									assert.same("b", symbol)
									return { absolute_path = file }
								end,
							},
						},
					}
				end,
			}
		end

		assert.same(file, diffview.anchor_path())
	end)

	it("returns nil without the lib api or the symbol", function()
		local buf = vim.api.nvim_create_buf(false, false)
		vim.api.nvim_buf_set_name(buf, "diffview:///repo/.git/abc/a.lua")
		vim.api.nvim_set_current_buf(buf)

		assert.is_nil(diffview.anchor_path())

		vim.b[buf].diffview_symbol = "b"
		package.preload["diffview.lib"] = function()
			return {
				get_current_view = function()
					return {}
				end,
			}
		end

		assert.is_nil(diffview.anchor_path())
	end)
end)

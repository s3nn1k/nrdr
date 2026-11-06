local M = {}

function M.anchor_path()
	local symbol = vim.b.diffview_symbol
	if not symbol then
		return nil
	end
	local ok_lib, lib = pcall(require, "diffview.lib")
	if not ok_lib then
		return nil
	end
	local ok_view, view = pcall(function()
		return lib.get_current_view()
	end)
	if not ok_view or not view or not view.cur_entry then
		return nil
	end
	local ok_file, file = pcall(function()
		return view.cur_entry.layout:get_file_for(symbol)
	end)
	if not ok_file or not file or not file.absolute_path then
		return nil
	end
	return file.absolute_path
end

return M

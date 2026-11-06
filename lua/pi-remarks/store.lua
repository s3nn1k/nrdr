local M = {}

local remarks = {}

function M.all()
	return remarks
end

function M.add(remark)
	remarks[#remarks + 1] = remark
end

function M.remove_index(index)
	table.remove(remarks, index)
end

function M.keep(predicate)
	local kept = {}
	for _, remark in ipairs(remarks) do
		if predicate(remark) then
			kept[#kept + 1] = remark
		end
	end
	remarks = kept
end

function M.clear()
	remarks = {}
end

return M

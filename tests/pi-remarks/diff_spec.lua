local diff = require("pi-remarks.diff")

local function hunk(header, body)
	return { header = header, body = body }
end

local two_hunk_diff = table.concat({
	"diff --git a/src/pay.go b/src/pay.go",
	"index 3f2a..91bc 100644",
	"--- a/src/pay.go",
	"+++ b/src/pay.go",
	"@@ -36,9 +36,14 @@ func submitOrder(o Order) error {",
	" func submitOrder(o Order) error {",
	"-\titems := flatten(o.Groups)",
	"+\titems, err := flatten(o.Groups)",
	"+\tif err != nil {",
	"+\t\treturn err",
	"+\t}",
	" ",
	"@@ -88,6 +93,11 @@ func settle(o Order) {",
	" func settle(o Order) {",
	'+\tlog.Printf("settle %v", o)',
	" \tpost(o)",
	"+\taudit(o)",
	" }",
}, "\n")

describe("parse_hunks", function()
	it("parses headers with counts and trailing context", function()
		local hunks = diff.parse_hunks(two_hunk_diff)
		assert.same(2, #hunks)
		assert.same("@@ -36,9 +36,14 @@ func submitOrder(o Order) error {", hunks[1].header)
		assert.same(36, hunks[1].new_start)
		assert.same(14, hunks[1].new_count)
		assert.same(93, hunks[2].new_start)
		assert.same(11, hunks[2].new_count)
	end)

	it("collects prefixed body lines without the header", function()
		local hunks = diff.parse_hunks(two_hunk_diff)
		assert.same({
			" func submitOrder(o Order) error {",
			"-\titems := flatten(o.Groups)",
			"+\titems, err := flatten(o.Groups)",
			"+\tif err != nil {",
			"+\t\treturn err",
			"+\t}",
			" ",
		}, hunks[1].body)
	end)

	it("defaults the count to one for single-line hunks", function()
		local hunks = diff.parse_hunks("@@ -5 +5 @@\n context\n+added\n")
		assert.same(1, #hunks)
		assert.same(5, hunks[1].new_start)
		assert.same(1, hunks[1].new_count)
	end)

	it("returns nothing for a clean file diff", function()
		local headers_only = table.concat({
			"diff --git a/src/pay.go b/src/pay.go",
			"index 3f2a..91bc 100644",
			"--- a/src/pay.go",
			"+++ b/src/pay.go",
		}, "\n")
		assert.same({}, diff.parse_hunks(headers_only))
	end)
end)

describe("select_hunk", function()
	local hunks = diff.parse_hunks(two_hunk_diff)

	it("selects the hunk containing the remark range", function()
		assert.same(hunks[1], diff.select_hunk(hunks, 40, 45))
	end)

	it("selects nothing past the hunks", function()
		assert.is_nil(diff.select_hunk(hunks, 120, 130))
	end)

	it("selects nothing in the gap between hunks", function()
		assert.is_nil(diff.select_hunk(hunks, 60, 70))
	end)

	it("selects the first hunk when the remark range spans two", function()
		assert.same(hunks[1], diff.select_hunk(hunks, 36, 95))
	end)
end)

describe("match_hunk", function()
	it("returns the header and body of the matching hunk", function()
		local matched = diff.match_hunk(two_hunk_diff, 40, 45)
		assert.same("@@ -36,9 +36,14 @@ func submitOrder(o Order) error {", matched.header)
		assert.same(7, #matched.body)
	end)

	it("returns nil without a match", function()
		assert.is_nil(diff.match_hunk(two_hunk_diff, 120, 130))
	end)
end)

describe("snapshot", function()
	local repo

	local function git(...)
		return vim.system({ "git", "-C", repo, ... }, { text = true }):wait()
	end

	before_each(function()
		repo = vim.fs.normalize(vim.fn.tempname()) .. "-repo"
		vim.fn.mkdir(repo, "p")
		assert.same(0, git("init").code)
		git("-c", "user.name=t", "-c", "user.email=t@t", "commit", "--allow-empty", "-m", "init")
		local file = repo .. "/src/pay.go"
		vim.fn.mkdir(vim.fs.dirname(file), "p")
		vim.fn.writefile({ "line one", "line two" }, file)
		git("add", "src/pay.go")
		assert.same(0, git("-c", "user.name=t", "-c", "user.email=t@t", "commit", "-m", "file").code)
	end)

	after_each(function()
		vim.fn.delete(repo, "rf")
	end)

	it("snapshots the hunk overlapping the remark range", function()
		vim.fn.writefile({ "line one edited", "line two", "line three" }, repo .. "/src/pay.go")
		local snapshot = diff.snapshot(repo .. "/src/pay.go", 1, 1, "HEAD")
		assert.truthy(snapshot)
		assert.truthy(snapshot.header:find("^@@ %-1,2 %+1,3 @@"))
		assert.same({ "-line one", "+line one edited", " line two", "+line three" }, snapshot.body)
	end)

	it("returns nil for a remark range outside the diff", function()
		vim.fn.writefile({ "line one edited" }, repo .. "/src/pay.go")
		assert.is_nil(diff.snapshot(repo .. "/src/pay.go", 9, 9, "HEAD"))
	end)

	it("returns nil quietly outside a git repository", function()
		local plain = vim.fs.normalize(vim.fn.tempname()) .. "-plain"
		vim.fn.mkdir(plain, "p")
		local file = plain .. "/a.lua"
		vim.fn.writefile({ "x" }, file)
		local notifications = {}
		local original_notify = vim.notify
		vim.notify = function(message, level)
			table.insert(notifications, { message = message, level = level })
		end
		local snapshot = diff.snapshot(file, 1, 1, "HEAD")
		vim.notify = original_notify
		assert.is_nil(snapshot)
		assert.same(0, #notifications)
	end)

	it("warns with a stderr snippet on other git failures", function()
		local file = repo .. "/src/pay.go"
		local notifications = {}
		local original_notify = vim.notify
		vim.notify = function(message, level)
			table.insert(notifications, { message = message, level = level })
		end
		local snapshot = diff.snapshot(file, 1, 1, "--pi-remarks-invalid-base")
		vim.notify = original_notify
		assert.is_nil(snapshot)
		assert.same(1, #notifications)
		assert.same(vim.log.levels.WARN, notifications[1].level)
	end)
end)

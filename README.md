# pi-remarks

Neovim plugin: collect code-review remarks for a project and hand them to a pi agent through `herdr`.

- `<leader>pc` (n/v) - stack a remark for the cursor line (+ count) or the visual selection; a floating popup takes the comment (`ZZ` confirm, `q` cancel).
- Each remark snapshots its diff hunk at add time (`git diff -U3 <diff_base> -- <file>`); the picker preview and the sent message render it next to the comment.
- `<leader>pb` - picker over the stored remarks: `<CR>` jump, `<C-d>` delete, `<C-e>` edit, `<C-x>` clear, `<C-s>` send; telescope when available, otherwise `vim.ui.select`.
- `<leader>ps` - send all remarks as markdown to an agent picked from `herdr agent list` (project `cwd` first); the background wait covers the turn starting and finishing.
- Remarks live in memory for the lifetime of the nvim session; the stack holds only the unsent remainder, sent remarks are removed right after a successful send.

## Dependencies

- `herdr` - agent transport (`agent list`, `agent prompt`, `agent wait`)
- telescope.nvim - loaded by the spec; pickers fall back to `vim.ui.select` without it
- plenary.nvim - tests only

## Setup

`setup()` keys are optional: `herdr_bin` (`"herdr"`), `wait_timeout_ms` (`600000`), `turn_start_timeout_ms` (`15000`), `diff_base` (`"HEAD"`).

## lazy.nvim spec

```lua
{
	dir = vim.fn.expand("~/projects/personal/pi-remarks"),
	dependencies = { "nvim-telescope/telescope.nvim" },
	init = function()
		vim.keymap.set("n", "<leader>pc", function() require("pi-remarks").add_line(vim.v.count) end, { desc = "pi-remarks: add remark" })
		vim.keymap.set("v", "<leader>pc", function() require("pi-remarks").add_range(vim.fn.line("'<"), vim.fn.line("'>")) end, { desc = "pi-remarks: add remark" })
		vim.keymap.set("n", "<leader>pb", function() require("pi-remarks").pick() end, { desc = "pi-remarks: browse remarks" })
		vim.keymap.set("n", "<leader>ps", function() require("pi-remarks").send() end, { desc = "pi-remarks: send remarks" })
	end,
}
```

Gates: `make fmt` / `make lint` (stylua), `make test` (plenary), `make smoke`.

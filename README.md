# pi-remarks

Neovim plugin: collect code-review remarks for a project and deliver them to a pi agent
through `herdr`.

- `:PiRemarksAdd [range]` - stack a remark for the cursor line, an explicit range
  (`:.,+2PiRemarksAdd`) or a visual selection; a floating popup takes the comment
  (`ZZ` confirm, `ZQ` cancel).
- `:PiRemarks` - stack buffer `pi-remarks://<root>`: `d` delete, `e` edit, `<CR>`
  jump to file:line, `S` send unsent, `C` clear all.
- `:PiRemarksSend` - send the unsent remarks as markdown to the herdr agent running in
  the project (`cwd` match, otherwise pick from all agents); the agent's turn is then
  awaited in the background.
- Remarks persist per project root (`getcwd()` at add time) in
  `stdpath("state")/pi-remarks/<sha256>.json`.

## Dependencies

- `herdr` - agent transport (`agent list`, `agent prompt`, `agent wait`)
- plenary.nvim - tests only

## Setup

`setup()` keys are optional: `herdr_bin` (`"herdr"`), `wait_timeout_ms` (`600000`).

## lazy.nvim spec

```lua
{
	dir = vim.fn.expand("~/projects/personal/pi-remarks"),
	init = function()
		vim.keymap.set({ "n", "v" }, "<leader>ma", ":PiRemarksAdd<CR>", { desc = "pi-remarks: add remark" })
		vim.keymap.set("n", "<leader>ml", ":PiRemarks<CR>", { desc = "pi-remarks: list" })
		vim.keymap.set("n", "<leader>ms", ":PiRemarksSend<CR>", { desc = "pi-remarks: send" })
	end,
}
```

Gates: `make fmt` / `make lint` (stylua), `make test` (plenary), `make smoke`.

# nrdr

Minimal Neovim extension for herdr: stack code-review remarks while you read
code or a diff, then steer them into any herdr-managed coding agent (pi, Claude
Code, Codex, and the rest herdr supports) as one message.

- `hc` (normal, count) / visual `hc` - stack a remark for a line or selection; a
  floating ` comment ` popup takes the text (`ZZ` confirm, `q` cancel).
- `hb` - telescope picker over the stack: `file:line` rows, full comment (and
  the snapshotted diff hunk) in the preview; `<CR>` jump in the current window,
  `<C-d>` delete, `<C-e>` edit, `<C-s>` send, `<C-x>` clear all after a confirm.
- `hs` - pick a herdr agent pane and send the stack as one message; sent
  remarks are dropped, the agent's turn is awaited in the background
  (`working` first, then `idle`).
- Adding from a diffview file snapshots the containing hunk (trimmed to a ±10
  line window with `…` markers) into the remark; the left (old) diff side is
  refused through the `diffview_symbol` marker.
- The stack lives in memory for the nvim session; no files are written.

## Dependencies

- `herdr` on PATH - agent transport (`agent list`, `agent prompt`, `agent wait`)
- telescope.nvim - loaded by the spec; pickers fall back to `vim.ui.select`
- plenary.nvim - tests only

## Setup

`setup()` keys are optional: `herdr_bin` (`"herdr"`), `wait_timeout_ms`
(`600000`), `turn_start_timeout_ms` (`15000`), `diff_base` (`"HEAD"`).

## Gates

`make fmt` / `make lint` (stylua), `make test` (plenary), `make smoke`.

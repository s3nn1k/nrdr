# nrdr

Minimal Neovim extension for herdr: stack code-review remarks while you read
code or a diff, then steer them into any herdr-managed coding agent (pi, Claude
Code, Codex, and the rest herdr supports) as one message.

- `hc` (normal, count) / visual `hc` - stack a remark for a line or selection
  (`:N` / `:N-M`); a floating ` comment ` popup takes the text (`ZZ` confirm,
  `q` cancel).
- `hb` - telescope picker over the stack (action hints in the title):
  `file:line` rows, full block in the preview; `<CR>` jump, `<C-d>` delete,
  `<C-e>` edit (the picker closes; reopen with `hb`), `<C-s>` send, `<C-x>` clear
  all after a `Да/Нет` confirm.
- `hs` - pick a herdr agent pane and send the stack as one message; sent
  remarks are dropped, the agent's turn is awaited in the background
  (`working` first, then `idle`).
- A remark is just `файл:line(s)` + `комментарий` - no diff snapshots; the
  agent picks up context itself. Old diff sides are refused through the
  `diffview_symbol` marker, diffview revision panes resolve to real paths.
- The stack lives in memory for the nvim session; no files are written.

## Dependencies

- `herdr` on PATH - agent transport (`agent list`, `agent prompt`, `agent wait`)
- telescope.nvim - loaded by the spec; pickers fall back to `vim.ui.select`
- plenary.nvim - tests only

## Setup

`setup()` keys are optional: `herdr_bin` (`"herdr"`), `wait_timeout_ms`
(`600000`), `turn_start_timeout_ms` (`15000`).

## Gates

`make fmt` / `make lint` (stylua), `make test` (plenary), `make smoke`.

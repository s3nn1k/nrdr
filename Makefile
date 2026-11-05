.PHONY: fmt lint test smoke

fmt:
	stylua lua tests

lint:
	stylua --check lua tests

test:
	nvim -n --headless -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/pi-remarks"

smoke:
	nvim --headless -u tests/minimal_init.lua +'lua require("pi-remarks")' +qa

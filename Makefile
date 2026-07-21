.PHONY: test

LUA ?= lua

test:
	$(LUA) tests/run.lua

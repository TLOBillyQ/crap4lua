.PHONY: test

LUA ?= lua
# luacheck is a runtime dependency (LuaRocks). On machines without a
# luarocks-visible install, point LUACHECK_DIR at its module directory.
LUACHECK_DIR ?= /opt/homebrew/Cellar/luacheck/1.2.0_1/libexec/share/lua/5.4

test:
	LUA_PATH="$(LUACHECK_DIR)/?.lua;$(LUACHECK_DIR)/?/init.lua;;" $(LUA) tests/run.lua

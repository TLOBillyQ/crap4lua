.PHONY: test

LUA ?= /opt/homebrew/opt/lua@5.4/bin/lua5.4
# luacheck is a runtime dependency (LuaRocks). On machines without a
# luarocks-visible install, point LUACHECK_DIR at its module directory.
LUACHECK_DIR ?= /opt/homebrew/Cellar/luacheck/1.2.0_1/libexec/share/lua/5.4
# luaunit is a test-only dependency (LuaRocks). Point LUAROCKS_DIR at the
# Lua 5.4 module tree where it is installed.
LUAROCKS_DIR ?= $(HOME)/.luarocks/share/lua/5.4

test:
	LUA_PATH="$(LUACHECK_DIR)/?.lua;$(LUACHECK_DIR)/?/init.lua;$(LUAROCKS_DIR)/?.lua;$(LUAROCKS_DIR)/?/init.lua;;" $(LUA) tests/run.lua

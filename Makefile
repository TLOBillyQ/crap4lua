GO_BIN := bin/crap4lua-go

.PHONY: build-go test-go test-lua test

build-go:
	go build -o $(GO_BIN) ./cmd/crap4lua-go

test-go:
	go test ./...

test-lua:
	lua tests/run.lua

test: test-go test-lua

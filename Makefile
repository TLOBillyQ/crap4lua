GO_BIN := bin/crap4lua

.PHONY: build test-go test-lua test

build:
	go build -o $(GO_BIN) ./cmd/crap4lua

test-go:
	go test ./...

test-lua:
	lua tests/run.lua

test: test-go test-lua

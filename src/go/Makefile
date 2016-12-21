GO := go
pkgs   = $(shell $(GO) list ./... | grep -v /vendor/)
VERSION=$(git describe --tags)                                                   
BUILD=$(date +%FT%T%z)

PREFIX=$(shell pwd)
BIN_DIR=$(shell git rev-parse --show-toplevel)/bin
LDFLAGS="-w -s -X main.Version=${VERSION} -X main.Build=${BUILD}"


all: format gox test

style:
	@echo ">> checking code style"
	@! gofmt -d $(shell find . -path ./vendor -prune -o -name '*.go' -print) | grep '^'

test:
	@echo ">> running tests"
	@./runtests.sh

format:
	@echo ">> formatting code"
	@$(GO) fmt $(pkgs)

vet:
	@echo ">> vetting code"
	@$(GO) vet $(pkgs)

build-all: 
	@echo ">> building all binaries in $(BIN_DIR). OS & platform will be appended to the file name"
	@gox build -ldflags $(LDFLAGS) -osarch="linux/amd64 linux/386 darwin/amd64 darwin/386" -output=$(BIN_DIR)"/{{.Dir}}_{{.OS}}_{{.Arch}}" $(pkgs)

linux-amd64: 
	@echo ">> building linux/amd64 binaries in $(BIN_DIR)"
	gox -ldflags $(LDFLAGS) -osarch="linux/amd64" -output=$(BIN_DIR)"/{{.Dir}}" $(pkgs)

linux-386: 
	@echo ">> building linux/386 binaries in $(BIN_DIR)"
	gox -ldflags $(LDFLAGS) -osarch="linux/amd64" -output=$(BIN_DIR)"/{{.Dir}}" $(pkgs)

darwin-amd64: 
	@echo ">> building darwin/amd64 binaries in $(BIN_DIR)"
	gox -ldflags $(LDFLAGS) -osarch="darwin/amd64" -output=$(BIN_DIR)"/{{.Dir}}" $(pkgs)

darwin-386: 
	@echo ">> building darwin/386 binaries in $(BIN_DIR)"
	gox -ldflags $(LDFLAGS) -osarch="darwin/386" -output=$(BIN_DIR)"/{{.Dir}}" $(pkgs)

.PHONY: all style format build test vet tarball 

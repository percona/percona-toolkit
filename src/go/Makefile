GO    := GO15VENDOREXPERIMENT=1 go
pkgs   = $(shell $(GO) list ./... | grep -v /vendor/)
VERSION=$(git describe --tags)                                                   
BUILD=$(date +%FT%T%z)

PREFIX=$(shell pwd)
BIN_DIR=$(shell pwd)


all: format build test

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

build: 
	@echo ">> building binaries"
	@$(GO) build -ldflags "-w -s -X main.Version=${VERSION} -X main.Build=${BUILD}"

.PHONY: all style format build test vet tarball 

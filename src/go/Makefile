GO := go
pkgs   = $(shell $(GO) list ./... | grep -v /vendor/)
VERSION=$(shell git describe --tags)                                                   
BUILD=$(shell date +%FT%T%z)
GOVERSION=$(shell go version | cut --delimiter=" " -f3)

PREFIX=$(shell pwd)
BIN_DIR=$(shell git rev-parse --show-toplevel)/bin
LDFLAGS="-X main.Version=${VERSION} -X main.Build=${BUILD} -X main.GoVersion=${GOVERSION}"


build-all: 
	@echo ">> building all binaries in ${BIN_DIR}. OS & platform will be appended to the file name"
	@echo "LDFLAGS: ${LDFLAGS}"
	@gox -ldflags=${LDFLAGS} -osarch="linux/amd64 linux/386 darwin/amd64" -output=${BIN_DIR}"/{{.Dir}}_{{.OS}}_{{.Arch}}" $(pkgs)

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

linux-amd64: 
	@echo ">> building linux/amd64 binaries in $(BIN_DIR)"
	gox -ldflags ${LDFLAGS} -osarch="linux/amd64" -output=${BIN_DIR}"/{{.Dir}}" $(pkgs)

linux-386: 
	@echo ">> building linux/386 binaries in $(BIN_DIR)"
	gox -ldflags ${LDFLAGS} -osarch="linux/amd64" -output=${BIN_DIR}"/{{.Dir}}" $(pkgs)

darwin-amd64: 
	@echo ">> building darwin/amd64 binaries in $(BIN_DIR)"
	gox -ldflags ${LDFLAGS} -osarch="darwin/amd64" -output=${BIN_DIR}"/{{.Dir}}" $(pkgs)

.PHONY: all style format build test vet tarball 

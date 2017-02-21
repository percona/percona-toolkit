GO := go
pkgs   = $(shell find . -type d -name "pt-mongodb*" -exec basename {} \;)
VERSION="3.0.1" 
BUILD=$(shell date +%FT%T%z)
GOVERSION=$(shell go version | cut --delimiter=" " -f3)

PREFIX=$(shell pwd)
TOP_DIR=$(shell git rev-parse --show-toplevel)
BIN_DIR=$(shell git rev-parse --show-toplevel)/bin
SRC_DIR=$(shell git rev-parse --show-toplevel)/src/go
LDFLAGS="-X main.Version=${VERSION} -X main.Build=${BUILD} -X main.GoVersion=${GOVERSION} -s -w"

.PHONY: all style format build test vet tarball linux-amd64

linux-amd64: 
	@echo "Building linux/amd64 binaries in ${BIN_DIR}"
	@cd ${TOP_DIR} && glide install -v
	@$(foreach pkg,$(pkgs),rm -f ${BIN_DIR}/$(pkg) 2> /dev/null;)
	@$(foreach pkg,$(pkgs),GOOS=linux GOARCH=amd64 go build -ldflags ${LDFLAGS} -o ${BIN_DIR}/$(pkg) ./$(pkg);)

linux-386: 
	@echo "Building linux/386 binaries in ${BIN_DIR}"
	@cd ${TOP_DIR} && glide install -v
	@$(foreach pkg,$(pkgs),rm -f ${BIN_DIR}/$(pkg) 2> /dev/null;)
	@$(foreach pkg,$(pkgs),GOOS=linux GOARCH=386 go build -ldflags ${LDFLAGS} -o ${BIN_DIR}/$(pkg) ./$(pkg);)

darwin-amd64: 
	@echo "Building darwin/amd64 binaries in ${BIN_DIR}"
	@cd ${TOP_DIR} && glide install -v
	@$(foreach pkg,$(pkgs),rm -f ${BIN_DIR}/$(pkg) 2> /dev/null;)
	@$(foreach pkg,$(pkgs),GOOS=darwin GOARCH=amd64 go build -ldflags ${LDFLAGS} -o ${BIN_DIR}/$(pkg) ./$(pkg);)

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


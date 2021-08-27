help:                 ## Display this help message.
	@echo "Please use \`make <target>\` where <target> is one of:"
	@grep '^[a-zA-Z]' $(MAKEFILE_LIST) | \
		awk -F ':.*?## ' 'NF==2 {printf "  %-26s%s\n", $$1, $$2}'

GO := go
pkgs = $(shell find . -type d -name "pt-*" -exec basename {} \;)
VERSION=$(shell git describe --abbrev=0 --tags)
BUILD=$(shell date +%FT%T%z)
GOVERSION=$(shell go version | cut --delimiter=" " -f3)
COMMIT=$(shell git rev-list -1 HEAD)
GOUTILSDIR ?= $(GOPATH)/bin
FILES = $(shell find . -type f -name '*.go' -not -path "./vendor/*")

PREFIX=$(shell pwd)
TOP_DIR=$(shell git rev-parse --show-toplevel)
BIN_DIR=$(shell git rev-parse --show-toplevel)/bin
SRC_DIR=$(shell git rev-parse --show-toplevel)/src/go
LDFLAGS="-X main.Version=${VERSION} -X main.Build=${BUILD} -X main.GoVersion=${GOVERSION} -X main.Commit=${COMMIT} -s -w"

TEST_PSMDB_VERSION?=4.0
TEST_MONGODB_FLAVOR?=percona/percona-server-mongodb
TEST_MONGODB_ADMIN_USERNAME?=admin
TEST_MONGODB_ADMIN_PASSWORD?=admin123456
TEST_MONGODB_USERNAME?=test
TEST_MONGODB_PASSWORD?=123456

TEST_MONGODB_STANDALONE_PORT?=27017

TEST_MONGODB_MONGOS_PORT?=17000

TEST_MONGODB_S1_RS?=rs1
TEST_MONGODB_S1_PRIMARY_PORT?=17001
TEST_MONGODB_S1_SECONDARY1_PORT?=17002
TEST_MONGODB_S1_SECONDARY2_PORT?=17003

TEST_MONGODB_S2_RS?=rs2
TEST_MONGODB_S2_PRIMARY_PORT?=17004
TEST_MONGODB_S2_SECONDARY1_PORT?=17005
TEST_MONGODB_S2_SECONDARY2_PORT?=17006

TEST_MONGODB_CONFIGSVR_RS?=csReplSet
TEST_MONGODB_CONFIGSVR1_PORT?=17007
TEST_MONGODB_CONFIGSVR2_PORT?=17008
TEST_MONGODB_CONFIGSVR3_PORT?=17009

TEST_MONGODB_S3_RS?=rs3
TEST_MONGODB_S3_PRIMARY_PORT?=17021
TEST_MONGODB_S3_SECONDARY1_PORT?=17022
TEST_MONGODB_S3_SECONDARY2_PORT?=17023

AWS_ACCESS_KEY_ID?=
AWS_SECRET_ACCESS_KEY?=

MINIO_PORT=9000
MINIO_ACCESS_KEY_ID=example00000
MINIO_SECRET_ACCESS_KEY=secret00000
export MINIO_ACCESS_KEY_ID
export MINIO_SECRET_ACCESS_KEY

.PHONY: all style format build test vet tarball linux-amd64

$(GOUTILSDIR)/dep:
	go get -u github.com/golang/dep/cmd/dep

define TEST_ENV
	AWS_ACCESS_KEY_ID=$(AWS_ACCESS_KEY_ID) \
	AWS_SECRET_ACCESS_KEY=$(AWS_SECRET_ACCESS_KEY) \
	GOCACHE=$(GOCACHE) \
	GOLANG_DOCKERHUB_TAG=$(GOLANG_DOCKERHUB_TAG) \
	TEST_MONGODB_ADMIN_USERNAME=$(TEST_MONGODB_ADMIN_USERNAME) \
	TEST_MONGODB_ADMIN_PASSWORD=$(TEST_MONGODB_ADMIN_PASSWORD) \
	TEST_MONGODB_USERNAME=$(TEST_MONGODB_USERNAME) \
	TEST_MONGODB_PASSWORD=$(TEST_MONGODB_PASSWORD) \
	TEST_MONGODB_S1_RS=$(TEST_MONGODB_S1_RS) \
	TEST_MONGODB_STANDALONE_PORT=$(TEST_MONGODB_STANDALONE_PORT) \
	TEST_MONGODB_S1_PRIMARY_PORT=$(TEST_MONGODB_S1_PRIMARY_PORT) \
	TEST_MONGODB_S1_SECONDARY1_PORT=$(TEST_MONGODB_S1_SECONDARY1_PORT) \
	TEST_MONGODB_S1_SECONDARY2_PORT=$(TEST_MONGODB_S1_SECONDARY2_PORT) \
	TEST_MONGODB_S2_RS=$(TEST_MONGODB_S2_RS) \
	TEST_MONGODB_S2_PRIMARY_PORT=$(TEST_MONGODB_S2_PRIMARY_PORT) \
	TEST_MONGODB_S2_SECONDARY1_PORT=$(TEST_MONGODB_S2_SECONDARY1_PORT) \
	TEST_MONGODB_S2_SECONDARY2_PORT=$(TEST_MONGODB_S2_SECONDARY2_PORT) \
	TEST_MONGODB_S3_RS=$(TEST_MONGODB_S3_RS) \
	TEST_MONGODB_S3_PRIMARY_PORT=$(TEST_MONGODB_S3_PRIMARY_PORT) \
	TEST_MONGODB_S3_SECONDARY1_PORT=$(TEST_MONGODB_S3_SECONDARY1_PORT) \
	TEST_MONGODB_S3_SECONDARY2_PORT=$(TEST_MONGODB_S3_SECONDARY2_PORT) \
	TEST_MONGODB_CONFIGSVR_RS=$(TEST_MONGODB_CONFIGSVR_RS) \
	TEST_MONGODB_CONFIGSVR1_PORT=$(TEST_MONGODB_CONFIGSVR1_PORT) \
	TEST_MONGODB_CONFIGSVR2_PORT=$(TEST_MONGODB_CONFIGSVR2_PORT) \
	TEST_MONGODB_CONFIGSVR3_PORT=$(TEST_MONGODB_CONFIGSVR3_PORT) \
	TEST_MONGODB_MONGOS_PORT=$(TEST_MONGODB_MONGOS_PORT) \
	TEST_PSMDB_VERSION=$(TEST_PSMDB_VERSION) \
	TEST_MONGODB_FLAVOR=$(TEST_MONGODB_FLAVOR)
endef

env:
	@echo $(TEST_ENV) | tr ' ' '\n' >.env

env-up: env					## Start MongoDB docker containers cluster
	TEST_PSMDB_VERSION=$(TEST_PSMDB_VERSION) \
	docker-compose up \
	--detach \
	--force-recreate \
	--always-recreate-deps \
	--renew-anon-volumes \
	init 
	docker/test/init-cluster-wait.sh

env-down: env				## Clean-up MongoDB docker containers cluster
	docker-compose down -v
	rm .env

linux-amd64: 				## Build Mongo tools for linux-amd64
	@echo "Building linux/amd64 binaries in ${BIN_DIR}"
	@cd ${TOP_DIR} && go get ./...
	@$(foreach pkg,$(pkgs),rm -f ${BIN_DIR}/$(pkg) 2> /dev/null;)
	@$(foreach pkg,$(pkgs),GOOS=linux GOARCH=amd64 go build -ldflags ${LDFLAGS} -o ${BIN_DIR}/$(pkg) ./$(pkg);)

linux-386: 					## Build Mongo tools for linux-386
	@echo "Building linux/386 binaries in ${BIN_DIR}"
	@cd ${TOP_DIR} && go get ./...
	@$(foreach pkg,$(pkgs),rm -f ${BIN_DIR}/$(pkg) 2> /dev/null;)
	@$(foreach pkg,$(pkgs),GOOS=linux GOARCH=386 go build -ldflags ${LDFLAGS} -o ${BIN_DIR}/$(pkg) ./$(pkg);)

darwin-amd64:				## Build Mongo tools for darwin-amd64 (MacOS) 
	@echo "Building darwin/amd64 binaries in ${BIN_DIR}"
	@cd ${TOP_DIR} && go get ./...
	@$(foreach pkg,$(pkgs),rm -f ${BIN_DIR}/$(pkg) 2> /dev/null;)
	@$(foreach pkg,$(pkgs),GOOS=darwin GOARCH=amd64 go build -ldflags ${LDFLAGS} -o ${BIN_DIR}/$(pkg) ./$(pkg);)

style:						## Check code style
	@echo ">> checking code style"
	@! gofmt -d $(shell find . -path ./vendor -prune -o -name '*.go' -print) | grep '^'

test:						## Run tests
	@echo ">> running tests"
	@./runtests.sh

format:                         ## Format source code.
	gofumpt -w -s $(FILES)
	gofumports -local github.com/percona/pmm-managed -l -w $(FILES)

vet:						## Run vet on Go code
	@echo ">> vetting code"
	@$(foreach pkg,$(pkgs), cd $(TOP_DIR)/src/go/$(pkg); go vet ./... ;)


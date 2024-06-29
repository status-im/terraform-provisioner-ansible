BINARY_NAME=terraform-provisioner-ansible
PLUGINS_DIR=~/.terraform.d/plugins
CURRENT_DIR=$(dir $(realpath $(firstword $(MAKEFILE_LIST))))

CI_ANSIBLE_VERSION=2.9.15
CI_GOLANG_VERSION=1.15.3
CI_PROJECT_PATH=/go/src/github.com/radekg/terraform-provisioner-ansible

TEST_TIMEOUT?=120s

OS := $(shell uname -s | tr A-Z a-z)
ifeq ($(OS),darwin)
    OS := darwin
else ifeq ($(OS),linux)
    OS := linux
else
    $(error Unsupported OS: $(OS))
endif

ARCH := $(shell uname -m)
ifeq ($(ARCH),x86_64)
    ARCH := amd64
else ifeq ($(ARCH),arm64)
    ARCH := arm64
else
    $(error Unsupported architecture: $(ARCH))
endif

.PHONY: plugins-dir
plugins-dir:
	mkdir -p ${PLUGINS_DIR}

.PHONY: lint
lint:
	@which golint > /dev/null || go get -u golang.org/x/lint/golint
	golint

.PHONY: update-dependencies
update-dependencies:
	go get -v ./...

.PHONY: check-golang-version
check-golang-version:
	./bin/check-golang-version.sh

.PHONY: ci-build-image
ci-build-image:
	docker build --build-arg ANSIBLE_VERSION=${CI_ANSIBLE_VERSION} \
		--force-rm \
		--no-cache \
		-t radekg/terraform-provisioner-ansible-ci:ansible-${CI_ANSIBLE_VERSION}-go-${CI_GOLANG_VERSION} -f .circleci/Dockerfile .circleci/

.PHONY: ci-run-tests
ci-run-tests:
	docker run --rm \
		-v $(shell pwd):${CI_PROJECT_PATH} \
		-ti radekg/terraform-provisioner-ansible-ci:ansible-${CI_ANSIBLE_VERSION}-go-${CI_GOLANG_VERSION} \
		/bin/sh -c 'cd ${CI_PROJECT_PATH} && make lint && make test-verbose'

.PHONY: build-linux
build-linux: check-golang-version plugins-dir
	CGO_ENABLED=0 GOOS=linux installsuffix=cgo go build -o ./${BINARY_NAME}-linux
	cp ./${BINARY_NAME}-linux ${PLUGINS_DIR}/${BINARY_NAME}
	rm ./${BINARY_NAME}-linux

.PHONY: build-darwin
build-darwin: check-golang-version plugins-dir
	CGO_ENABLED=0 GOOS=darwin installsuffix=cgo go build -o ./${BINARY_NAME}-darwin
	cp ./${BINARY_NAME}-darwin ${PLUGINS_DIR}/${BINARY_NAME}
	rm ./${BINARY_NAME}-darwin

# this rule must not be used directly
# this rule is invoked by the bin/build-release-binaries.sh script inside of a docker container where the build happens
.PHONY: build-release
build-release:
	CGO_ENABLED=0 GOOS=${OS} GOARCH=$(ARCH) installsuffix=cgo go build -o ${GOPATH}/bin/${BINARY_NAME}-$(OS)-$(ARCH)_${RELEASE_VERSION}

.PHONY: coverage
coverage:
	mkdir -p ${CURRENT_DIR}/.coverage
	go test -coverprofile=${CURRENT_DIR}/.coverage/cov.out -v ./...
	go tool cover -html=${CURRENT_DIR}/.coverage/cov.out \
		-o ${CURRENT_DIR}/.coverage/cov.html

.PHONY: test
test:
	go clean -testcache
	go test -timeout ${TEST_TIMEOUT} -cover

.PHONY: test-verbose
test-verbose:
	go clean -testcache
	go test -timeout ${TEST_TIMEOUT} -cover -v ./...

# Root Makefile used by SAM and local development.
#
# SAM sets ARTIFACTS_DIR to the staging directory for the function artifact.
# The binary must be named "bootstrap" for the provided.al2023 runtime.

BIN_NAME ?= bose-cloud-bridge
OUT_DIR ?= dist
GOOS_TARGET ?= linux
GOARCH_TARGET ?= arm64
CGO_ENABLED_TARGET ?= 0
AWS_REGION ?= eu-north-1
STACK_NAME ?= bose-bridge

.PHONY: help build build-local test lint fmt-check fix run-local sam-build deploy print-function-url clean build-BridgeFunction

help:
	@echo "Targets:"
	@echo "  make build-local   Build local binary to $(OUT_DIR)/$(BIN_NAME)"
	@echo "  make test          Run all tests (Go)"
	@echo "  make lint          Run static checks (fmt-check + go vet)"
	@echo "  make fmt-check     Fail if Go files are not gofmt-formatted"
	@echo "  make fix           Run go fix and format Go files"
	@echo "  make run-local     Run server locally"
	@echo "  make sam-build     Run SAM build in infra/aws"
	@echo "  make deploy        Deploy stack manually via SAM"
	@echo "  make print-function-url  Print FunctionURL output from CloudFormation"
	@echo "  make clean         Remove local build artifacts"
	@echo "  make build         Alias for build-local"

build: build-local

test:
	go test ./...

fmt-check:
	@files="$$(find cmd -type f -name '*.go')"; \
	if [ -n "$$files" ]; then \
		unformatted="$$(gofmt -l $$files)"; \
		if [ -n "$$unformatted" ]; then \
			echo "Unformatted Go files:"; \
			echo "$$unformatted"; \
			exit 1; \
		fi; \
	fi

lint: fmt-check
	go vet ./...

fix:
	go fix ./...
	@files="$$(find cmd -type f -name '*.go')"; \
	if [ -n "$$files" ]; then \
		gofmt -w $$files; \
	fi

build-local:
	@mkdir -p "$(OUT_DIR)"
	@echo "==> Building $(BIN_NAME) ($(GOOS_TARGET)/$(GOARCH_TARGET))"
	CGO_ENABLED="$(CGO_ENABLED_TARGET)" GOOS="$(GOOS_TARGET)" GOARCH="$(GOARCH_TARGET)" \
		go build -ldflags="-s -w" -o "$(OUT_DIR)/$(BIN_NAME)" ./cmd/bose-cloud-bridge
	@echo "==> Build complete: $(OUT_DIR)/$(BIN_NAME)"

run-local:
	go run ./cmd/bose-cloud-bridge

sam-build:
	cd infra/aws && sam build --template-file template.yaml --build-in-source

deploy:
	cd infra/aws && sam deploy \
		--stack-name "$(STACK_NAME)" \
		--capabilities CAPABILITY_IAM \
		--no-confirm-changeset \
		--no-fail-on-empty-changeset \
		--resolve-s3 \
		--region "$(AWS_REGION)"

print-function-url:
	aws cloudformation describe-stacks \
		--stack-name "$(STACK_NAME)" \
		--region "$(AWS_REGION)" \
		--query "Stacks[0].Outputs[?OutputKey=='FunctionURL'].OutputValue" \
		--output text

clean:
	rm -rf "$(OUT_DIR)"

build-BridgeFunction:
	GOOS=linux GOARCH=arm64 CGO_ENABLED=0 \
		go build -ldflags="-s -w" -o "$(ARTIFACTS_DIR)/bootstrap" \
		./cmd/bose-cloud-bridge

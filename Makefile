ARGS ?= status
CARGO ?= $(firstword $(wildcard $(HOME)/.cargo/bin/cargo /opt/homebrew/opt/rustup/bin/cargo) cargo)
export PATH := $(dir $(CARGO)):$(PATH)

.DEFAULT_GOAL := help
.PHONY: help build release run test fmt fmt-check lint verify install uninstall clean

help: ## Show this help
	@echo "maccafe"
	@echo
	@awk -F'##' '/^[a-z-]+:.*##/ { \
		split($$1, target, ":"); sub(/^ +/, "", $$2); \
		printf "  \033[1m%-12s\033[0m %s\n", target[1], $$2 }' $(MAKEFILE_LIST)

build: ## Build the debug binary
	$(CARGO) build

release: ## Build the optimized binary
	$(CARGO) build --release

run: ## Run the CLI, for example: make run ARGS="on --duration 2h"
	$(CARGO) run -- $(ARGS)

test: ## Run the tests
	$(CARGO) test

fmt: ## Format the sources
	$(CARGO) fmt

fmt-check: ## Check the sources are formatted
	$(CARGO) fmt --check

lint: ## Run clippy and treat warnings as errors
	$(CARGO) clippy --all-targets -- -D warnings

verify: fmt-check lint test ## Check formatting, lint, and test

install: ## Install maccafe into ~/.cargo/bin
	$(CARGO) install --path .

uninstall: ## Remove the installed maccafe
	$(CARGO) uninstall maccafe

clean: ## Delete the build directory
	$(CARGO) clean

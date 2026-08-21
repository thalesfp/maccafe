ARGS ?= status
APP := Maccafe.app
STAGE := .build/$(APP)
INSTALLED := /Applications/$(APP)
SYMLINK := /usr/local/bin/maccafe
BINARY := .build/release/maccafe

.DEFAULT_GOAL := help
.PHONY: help build release run test fmt fmt-check lint verify bundle install uninstall clean

help: ## Show this help
	@echo "maccafe"
	@echo
	@awk -F'##' '/^[a-z-]+:.*##/ { \
		split($$1, target, ":"); sub(/^ +/, "", $$2); \
		printf "  \033[1m%-12s\033[0m %s\n", target[1], $$2 }' $(MAKEFILE_LIST)

build: ## Build the debug binary
	swift build

release: ## Build the optimized binary
	swift build -c release

run: ## Run the CLI, for example: make run ARGS="on --duration 2h"
	swift run maccafe $(ARGS)

test: ## Run the tests
	swift test

fmt: ## Format the sources
	swift format --in-place --recursive Sources Tests Package.swift

fmt-check: ## Check the sources are formatted
	swift format lint --strict --recursive Sources Tests Package.swift

lint: ## Build treating warnings as errors
	swift build -Xswiftc -warnings-as-errors

verify: fmt-check lint test ## Check formatting, lint, and test

bundle: release ## Assemble Maccafe.app
	rm -rf $(STAGE)
	mkdir -p $(STAGE)/Contents/MacOS $(STAGE)/Contents/Library/LaunchAgents
	cp $(BINARY) $(STAGE)/Contents/MacOS/maccafe
	cp Resources/Info.plist $(STAGE)/Contents/Info.plist
	cp Resources/me.thales.maccafe.agent.plist $(STAGE)/Contents/Library/LaunchAgents/
	codesign --force --sign - --identifier me.thales.maccafe $(STAGE)

# launchd pins the code signature it saw at registration, and renewing that pin
# needs the unregister to run in an earlier process than the register. The
# uninstall command blocks on unregisterWithCompletionHandler, which the header
# calls the point after which re-registering is safe. Measured on macOS 26.6.2,
# that is necessary but not sufficient: registering straight after it still
# re-pins the old signature and launchd kills the new agent with EX_CONFIG, so
# the recipe also settles before registering.
install: bundle ## Install the app, register the agent, and link the CLI
	rm -rf $(INSTALLED)
	cp -R $(STAGE) $(INSTALLED)
	$(INSTALLED)/Contents/MacOS/maccafe uninstall
	@sleep 5
	$(INSTALLED)/Contents/MacOS/maccafe install
	sudo ln -sf $(INSTALLED)/Contents/MacOS/maccafe $(SYMLINK)

# The app is deleted last: a registration launchd still holds would point at a
# bundle that is no longer there. Either bundle can unregister the other's
# registration, so the built one goes first: an interrupted copy can leave the
# installed executable in place without the plist SMAppService reads. A run with
# neither bundle stops instead of reporting success.
uninstall: ## Remove the agent, the CLI link, and the app
	@if [ -x "$(STAGE)/Contents/MacOS/maccafe" ]; then \
		"$(STAGE)/Contents/MacOS/maccafe" uninstall; \
	elif [ -x "$(INSTALLED)/Contents/MacOS/maccafe" ]; then \
		"$(INSTALLED)/Contents/MacOS/maccafe" uninstall; \
	else \
		echo "no maccafe bundle to unregister from; run 'make bundle' first"; \
		exit 1; \
	fi
	sudo rm -f $(SYMLINK)
	rm -rf $(INSTALLED)

clean: ## Delete the build directory
	swift package clean
	rm -rf $(STAGE)

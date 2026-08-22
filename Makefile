ARGS ?= status
APP := MacCafe.app
STAGE := .build/$(APP)
INSTALLED := /Applications/$(APP)
SYMLINK := /usr/local/bin/maccafe
LEGACY := $(HOME)/.cargo/bin/maccafe
LABEL := me.thales.maccafe.agent
BINARY := .build/release/maccafe

.DEFAULT_GOAL := help
.PHONY: help build release run test fmt fmt-check lint verify icon bundle install uninstall clean

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

icon: ## Redraw Resources/MacCafe.icns
	rm -rf .build/MacCafe.iconset
	swift Tools/MakeIcon.swift .build/MacCafe.iconset
	iconutil -c icns .build/MacCafe.iconset -o Resources/MacCafe.icns

bundle: release ## Assemble MacCafe.app
	rm -rf $(STAGE)
	mkdir -p $(STAGE)/Contents/MacOS $(STAGE)/Contents/Library/LaunchAgents $(STAGE)/Contents/Resources
	cp $(BINARY) $(STAGE)/Contents/MacOS/maccafe
	cp Resources/Info.plist $(STAGE)/Contents/Info.plist
	cp Resources/me.thales.maccafe.agent.plist $(STAGE)/Contents/Library/LaunchAgents/
	cp Resources/MacCafe.icns $(STAGE)/Contents/Resources/
	codesign --force --sign - --identifier me.thales.maccafe $(STAGE)

# The implementation before the rewrite installed itself into ~/.cargo/bin and
# held the assertion in a detached process of its own. This agent knows nothing
# about that holder and cannot stop it, so an upgrade is the last chance to.
# Removing that executable does not stop a holder already running, so the check
# that matters asks the ground truth, `pmset -g assertions`, rather than trusting
# the executable's absence. Everything that can refuse the install runs before
# the agent is unregistered, so a refusal leaves the working install untouched;
# the running agent's own pid is excluded from the search.
#
# launchd pins the code signature it saw at registration, and renewing that pin
# needs the unregister to run in an earlier process than the register. The
# uninstall command blocks on unregisterWithCompletionHandler, which the header
# calls the point after which re-registering is safe. Measured on macOS 26.6.2,
# that is necessary but not sufficient: registering straight after it still
# re-pins the old signature and launchd kills the new agent with EX_CONFIG, so
# the recipe also settles before registering.
#
# The built bundle does the unregistering, so nothing touches the installed one
# until that has succeeded: an upgrade that fails there leaves the working
# installation alone rather than stranding a new signature under an old pin. The
# reverse window is accepted: a copy that fails after the unregister leaves the
# old bundle unregistered, which says so and is fixed by running this again.
install: bundle ## Install the app, register the agent, and link the CLI
	@if [ -x "$(LEGACY)" ]; then \
		echo "releasing the hold left by the maccafe that came before the rewrite"; \
		"$(LEGACY)" off || { \
			echo "maccafe: $(LEGACY) still holds an assertion this agent cannot stop"; \
			exit 1; \
		}; \
		echo "maccafe: $(LEGACY) is obsolete; remove it with 'cargo uninstall maccafe'"; \
	fi
	@[ -d "$(dir $(SYMLINK))" ] || sudo mkdir -p "$(dir $(SYMLINK))"
	@assertions=$$(pmset -g assertions) || { \
		echo "maccafe: cannot read pmset assertions, so a holder from before the"; \
		echo "maccafe: rewrite cannot be ruled out; not installing"; \
		exit 1; \
	}; \
	mine=$$(launchctl print gui/$$UID/$(LABEL) 2>/dev/null \
		| awk '/^\tpid = /{print $$3}'); \
	stray=$$(printf '%s\n' "$$assertions" | grep 'named: "maccafe"' \
		| grep -oE 'pid [0-9]+' | awk '{print $$2}' | sort -u \
		| grep -vx "$${mine:-none}" | tr '\n' ' '); \
	if [ -n "$$stray" ]; then \
		echo "maccafe: a maccafe assertion is held by pid $$stray, which this agent"; \
		echo "maccafe: did not take; stop it with 'kill $$stray' and run this again"; \
		exit 1; \
	fi
	$(STAGE)/Contents/MacOS/maccafe uninstall
	@sleep 5
	rm -rf $(INSTALLED)
	cp -R $(STAGE) $(INSTALLED)
	$(INSTALLED)/Contents/MacOS/maccafe install
	sudo ln -sf $(INSTALLED)/Contents/MacOS/maccafe $(SYMLINK)
	@found=$$(command -v maccafe || true); \
	if [ "$$found" != "$(SYMLINK)" ]; then \
		echo "maccafe: installed, but maccafe still runs $$found"; \
		echo "maccafe: remove it, with 'cargo uninstall maccafe' if it is the old"; \
		echo "maccafe: one, or put $(dir $(SYMLINK)) earlier in PATH, then run this again"; \
		exit 1; \
	fi

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

VERSION := 2.0.0
# Makefile for multi-module CMake project with superbuild support
# Requires .modules configuration file
ifeq ($(OS),Windows_NT)
    # 1. Force Make to use sh.exe so your pipe/sed logic works
    SHELL := sh.exe

    # 2. Add the Git 'usr/bin' folder to the path (where grep and sed live)
    # Using ':=' for immediate evaluation. Adjust the path below if yours is different.
    GIT_BIN := /c/Program Files/Git/usr/bin
    export PATH := $(GIT_BIN):$(PATH)
endif

.PHONY: help clean config build stage install push pull update silent quiet noisy __autoupdate show-binary-dir default version check-update
# Keep autoupdate quiet to avoid leaking its shell script when make echoes commands
.SILENT: __autoupdate check-update
# Default target will be overridden later to implement requested behavior
.DEFAULT_GOAL := default

version:
	@echo $(VERSION)

# Auto-update implementation
# This runs once at the start of any requested target (except update/quiet/silent/noisy),
# checks the remote Makefile, and if an update is available it replaces this
# Makefile and aborts the current run with a message to re-run. If up-to-date,
# it optionally prints a message (suppressed by the 'silent' marker).

# Variables used by update/quiet(silent) targets
MAKEFILE_UPDATE_MARKER := .makefile_update_check
TODAY := $(shell date +%Y-%m-%d)
LAST_CHECK_TIME := $(shell [ -f "$(MAKEFILE_UPDATE_MARKER)" ] && cat $(MAKEFILE_UPDATE_MARKER) | cut -d' ' -f2- 2>/dev/null || echo "Never")

# Color output (use -e with echo for these to work)
BOLD := \033[1m
RED := \033[0;31m
GREEN := \033[0;32m
YELLOW := \033[1;33m
NC := \033[0m

# Export MSG and PRESET for recursive make calls
export MSG
export PRESET
export FORCE

# Ensure auto-update runs before the user's goals (skip for update/silent/noisy)
AUTOUPDATE_SKIP_GOALS := update quiet silent noisy
ifneq ($(strip $(MAKECMDGOALS)),)
  ifeq (,$(filter $(AUTOUPDATE_SKIP_GOALS),$(MAKECMDGOALS)))
    $(foreach g,$(MAKECMDGOALS),$(eval $(g): __autoupdate))
  endif
endif

__autoupdate:
	@IS_SILENT=0; [ "$(QUIET)" = "true" ] && IS_SILENT=1; \
	CUR_TIME=$$(date +%s); \
	LAST_CHECK=0; [ -f "$(MAKEFILE_UPDATE_MARKER)" ] && LAST_CHECK=$$(cat $(MAKEFILE_UPDATE_MARKER) | cut -d' ' -f1 2>/dev/null || echo 0); \
	DIFF=$$((CUR_TIME - LAST_CHECK)); \
	if [ "$$IS_SILENT" -ne 1 ]; then \
		printf "$(BOLD)MCA Build System v$(VERSION)$(NC)\n"; \
		printf "Last update check: $(YELLOW)$(LAST_CHECK_TIME)$(NC)\n\n"; \
	fi; \
	if [ "$$DIFF" -lt 600 ] && [ "$(FORCE)" != "TRUE" ]; then \
		exit 0; \
	fi; \
	if [ -z "$(REPO)" ]; then \
		if [ "$$IS_SILENT" -ne 1 ]; then printf "$(RED)REPO not defined in .modules, skipping update check.$(NC)\n"; fi; \
		exit 0; \
	fi; \
	TMP_DIR=$$(mktemp -d /tmp/makefile.repo.XXXXXX); \
	if [ "$$IS_SILENT" -ne 1 ]; then printf "Checking for updates from $(REPO)...\n"; fi; \
	if ! git clone --depth 1 "$(REPO)" "$$TMP_DIR" >/dev/null 2>&1; then \
		if [ "$$IS_SILENT" -ne 1 ]; then printf "$(RED)Failed to clone repo for update check.$(NC)\n"; fi; \
		rm -rf "$$TMP_DIR"; \
		exit 0; \
	fi; \
	NEW_VERSION=$$($(MAKE) --no-print-directory -C "$$TMP_DIR" version 2>/dev/null); \
	if [ -z "$$NEW_VERSION" ]; then \
		if [ "$$IS_SILENT" -ne 1 ]; then printf "$(RED)Failed to obtain version from cloned repo.$(NC)\n"; fi; \
		rm -rf "$$TMP_DIR"; \
		exit 0; \
	fi; \
	echo "$$CUR_TIME $$(date '+%Y-%m-%d %H:%M:%S')" > $(MAKEFILE_UPDATE_MARKER); \
	V1_MAJOR=$$(echo "$(VERSION)" | cut -d. -f1); V1_MINOR=$$(echo "$(VERSION)" | cut -d. -f2); V1_PATCH=$$(echo "$(VERSION)" | cut -d. -f3); \
	V2_MAJOR=$$(echo "$$NEW_VERSION" | cut -d. -f1); V2_MINOR=$$(echo "$$NEW_VERSION" | cut -d. -f2); V2_PATCH=$$(echo "$$NEW_VERSION" | cut -d. -f3); \
	NEWER=0; \
	if [ "$$V2_MAJOR" -gt "$$V1_MAJOR" ]; then NEWER=1; \
	elif [ "$$V2_MAJOR" -eq "$$V1_MAJOR" ] && [ "$$V2_MINOR" -gt "$$V1_MINOR" ]; then NEWER=1; \
	elif [ "$$V2_MAJOR" -eq "$$V1_MAJOR" ] && [ "$$V2_MINOR" -eq "$$V1_MINOR" ] && [ "$$V2_PATCH" -gt "$$V1_PATCH" ]; then NEWER=1; fi; \
	if [ "$$NEWER" -eq 1 ]; then \
		printf "$(GREEN)A newer version ($$NEW_VERSION) is available.$(NC)\n"; \
		cp "$$TMP_DIR/Makefile" Makefile; \
		rm -rf "$$TMP_DIR"; \
		printf "$(YELLOW)Makefile updated. Please re-run your command.$(NC)\n"; \
		exit 1; \
	fi; \
	OLDER=0; \
	if [ "$$V2_MAJOR" -lt "$$V1_MAJOR" ]; then OLDER=1; \
	elif [ "$$V2_MAJOR" -eq "$$V1_MAJOR" ] && [ "$$V2_MINOR" -lt "$$V1_MINOR" ]; then OLDER=1; \
	elif [ "$$V2_MAJOR" -eq "$$V1_MAJOR" ] && [ "$$V2_MINOR" -eq "$$V1_MINOR" ] && [ "$$V2_PATCH" -lt "$$V1_PATCH" ]; then OLDER=1; fi; \
	if [ "$$OLDER" -eq 1 ]; then \
		printf "$(YELLOW)Your local version ($(VERSION)) is newer than the repo version ($$NEW_VERSION).$(NC)\n"; \
		printf "Would you like to push your version to git? [y/N] "; \
		read ans; \
		if [ "$$ans" = "y" ] || [ "$$ans" = "Y" ]; then \
			$(MAKE) push; \
		fi; \
	else \
		if [ "$$IS_SILENT" -ne 1 ]; then printf "$(GREEN)Your Makefile is up to date.$(NC)\n"; fi; \
	fi; \
	rm -rf "$$TMP_DIR"

# Check for .modules file
ifeq (,$(wildcard ./.modules))
$(error $(RED)ERROR: .modules file not found in current directory$(NC))
endif

# Parse .modules file
MONOREPO := $(shell grep -E '^MONOREPO\s*:=' .modules 2>/dev/null | sed 's/.*:=\s*\([^ \t#]*\).*/\1/')
MODULES := $(shell grep -E '^MODULES\s*:=' .modules 2>/dev/null | sed 's/.*:=\s*\([^#]*\).*/\1/')
STAGEDIR := $(shell grep -E '^STAGEDIR\s*:=' .modules 2>/dev/null | sed 's/.*:=\s*\([^ \t#]*\).*/\1/')
PRESET_FILE := $(shell grep -E '^PRESET\s*:=' .modules 2>/dev/null | sed 's/.*:=\s*\(.*\)/\1/' | sed 's/^"\(.*\)"$$/\1/' | sed "s/^'\(.*\)'$$/\1/" | sed 's/[ \t]*#.*//' | sed 's/[ \t]*$$//')
EXECUTABLE := $(shell grep -E '^EXECUTABLE\s*:=' .modules 2>/dev/null | sed 's/.*:=\s*\([^ \t#]*\).*/\1/')
QUIET_VAL := $(shell grep -E '^QUIET\s*:=' .modules 2>/dev/null | sed 's/.*:=\s*\([^ \t#]*\).*/\1/')
REPO := $(shell grep -E '^REPO\s*:=' .modules 2>/dev/null | sed 's/.*:=\s*\([^ \t#]*\).*/\1/')

# Set defaults
STAGEDIR := $(if $(STAGEDIR),$(STAGEDIR),~/dev/stage)
PRESET := $(if $(PRESET),$(PRESET),$(if $(PRESET_FILE),$(PRESET_FILE),default))
EXECUTABLE := $(if $(EXECUTABLE),$(EXECUTABLE),false)
QUIET := $(if $(filter true,$(QUIET_VAL)),true,false)

# Extract both binaryDir and the environment variables from the preset
# This gets complex because we need to follow inheritance chains
define get_preset_info
$(shell python3 -c '
import json
import sys

def get_preset_with_inheritance(presets, name, visited=None):
    if visited is None:
        visited = set()
    if name in visited:
        return {}
    visited.add(name)

    preset = next((p for p in presets if p.get("name") == name), None)
    if not preset:
        return {}

    # Start with inherited values
    result = {"environment": {}, "cacheVariables": {}}
    for parent_name in preset.get("inherits", []):
        parent = get_preset_with_inheritance(presets, parent_name, visited)
        result["environment"].update(parent.get("environment", {}))
        result["cacheVariables"].update(parent.get("cacheVariables", {}))

    # Override with current preset values
    result["environment"].update(preset.get("environment", {}))
    result["cacheVariables"].update(preset.get("cacheVariables", {}))
    result["binaryDir"] = preset.get("binaryDir", "")

    return result

with open("CMakePresets.json") as f:
    data = json.load(f)

preset = get_preset_with_inheritance(data["configurePresets"], "$(PRESET)")
binary_dir = preset.get("binaryDir", "")

# Resolve environment variables in binaryDir
import re
def resolve_env(match):
    var_name = match.group(1)
    return preset["environment"].get(var_name, "")

binary_dir = re.sub(r"\$$env\{([^}]+)\}", resolve_env, binary_dir)
print(binary_dir, end="")
')
endef

BINARY_DIR := $(get_preset_info)

.PHONY: show-binary-dir
show-binary-dir:
	@echo "Preset: $(BOLD)$(PRESET)$(NC)"
	@echo "Binary Dir: $(BINARY_DIR)"

# Expand tilde in STAGEDIR
STAGEDIR := $(shell echo $(STAGEDIR))

# Get current directory name
CURRENT_DIR := $(notdir $(CURDIR))

# Validate current directory according to MONOREPO rules
ifeq ($(MONOREPO),)
    # Not a monorepo: must be in a module dir listed in MODULES
    ifeq (,$(filter $(CURRENT_DIR),$(MODULES)))
        $(error $(RED)ERROR: Current directory '$(CURRENT_DIR)' is not listed in MODULES$(NC))
    endif
    MODE := module
    MODULE_PREFIX := ..
else
    # Monorepo set
    ifeq ($(CURRENT_DIR),$(MONOREPO))
        MODE := monorepo
        MODULE_PREFIX := .
    else ifeq (,$(filter $(CURRENT_DIR),$(MODULES)))
        $(error $(RED)ERROR: Current directory '$(CURRENT_DIR)' must be '$(MONOREPO)' or one of: $(MODULES)$(NC))
    else
        MODE := module
        MODULE_PREFIX := ..
    endif
endif

# Date for auto-commit
DATE := $(shell date +%Y-%m-%d\ %H:%M:%S)
HOSTNAME := $(shell hostname 2>/dev/null || echo $$COMPUTERNAME)
ifeq ($(strip $(MSG)),)
    MSG := Pushed from $(HOSTNAME) $(DATE)
endif

# Helper functions
define validate_module
	$(if $(filter $(1),$(MODULES) All),,$(error $(RED)ERROR: '$(1)' is not a valid module. Must be one of: $(MODULES) All$(NC)))
endef

define check_module_exists
	$(if $(filter $(1),All),,$(if $(wildcard $(MODULE_PREFIX)/$(1)),,$(error $(RED)ERROR: Module directory '$(MODULE_PREFIX)/$(1)' does not exist$(NC))))
endef

# Build directory determination (from preset)
BUILD_DIR := build

# Auto-generate CMakePresets.json if it doesn't exist but the template does
ifeq (,$(wildcard CMakePresets.json))
ifneq (,$(wildcard cmake/templates/CMakePresets.in))
ifneq (,$(wildcard cmake/filter-presets.py))
$(shell python3 cmake/filter-presets.py cmake/templates/CMakePresets.in CMakePresets.json)
$(info Generated CMakePresets.json from cmake/templates/CMakePresets.in)
endif
endif
endif

# Helper: ensure CMakePresets.json exists before running CMake commands
define ensure_presets
	@if [ ! -f CMakePresets.json ] && [ -f cmake/templates/CMakePresets.in ] && [ -f cmake/filter-presets.py ]; then \
		printf "$(YELLOW)Generating CMakePresets.json...$(NC)\n"; \
		python3 cmake/filter-presets.py cmake/templates/CMakePresets.in CMakePresets.json || exit 1; \
	fi
endef

define run_config
	$(call ensure_presets)
	printf "$(GREEN)Configuring$(NC) with preset $(BOLD)$(PRESET)$(NC) "
	if [ ! -f "$(BINARY_DIR)/CMakeCache.txt" ]; then \
		printf "$(YELLOW)required, configuring...$(NC)\n"; \
		cmake -S . -B $(BINARY_DIR) --preset "$(PRESET)" || exit 1; \
	else \
		printf "$(GREEN)not required$(NC), skipping...\n"; \
	fi
endef

# Helper: build with preset when CMakePresets.json exists; otherwise configure and build in $(BUILD_DIR)
# Usage: $(call run_build,<cmake-args>,<destdir>)
# If destdir is provided, it will be set as DESTDIR environment variable
# Auto-configures if build directory doesn't exist
define run_build
	$(call run_config)
	$(if $(2),DESTDIR=$(2)) cmake --build $(BINARY_DIR) --preset "$(PRESET)" $(1)


	cmake --build --preset "$(PRESET)"
endef

help:
	@printf "$(GREEN)Multi-Module CMake Build System$(NC)\n"
	@printf "Mode: $(MODE)\n"
	@printf "Modules: $(MODULES)\n"
	@printf "Stage Dir: $(STAGEDIR)\n"
	@printf "Preset: $(BOLD)$(PRESET)$(NC)\n"
	@printf "Executable: $(EXECUTABLE)\n"
	@printf "\n"
	@printf "Available targets:\n"
	@printf "  make clean                  - Clean current module\n"
	@printf "  make config                 - Configure current module\n"
	@printf "  make build                  - Build current module (auto-configures if needed)\n"
	@printf "  make stage                  - Stage current module to STAGEDIR (unavailable if EXECUTABLE=true)\n"
	@printf "  make install                - Install current module (requires sudo; unavailable if EXECUTABLE=true)\n"
	@printf "  make clean-<Module|All>     - Clean specific module or all\n"
	@printf "  make config-<Module|All>    - Configure specific module or all\n"
	@printf "  make build-<Module|All>     - Build specific module or all\n"
	@printf "  make stage-<Module|All>     - Stage specific module or all\n"
	@printf "  make install-<Module|All>   - Install specific module or all\n"
	@printf "  make push [MSG=\"msg\"]       - Commit and push current module\n"
	@printf "  make push-<Module|All>      - Commit and push specific module or all\n"
	@printf "  make pull                   - Pull current module\n"
	@printf "  make pull-<Module|All>      - Pull specific module or all\n"
	@printf "  make update                 - Force update Makefile from repository\n"
	@printf "  make check-update           - Check for Makefile updates without updating\n"
	@printf "  make quiet                  - Suppress daily update check messages\n"
	@printf "  make noisy                  - Re-enable daily update check messages\n"
	@printf "  show-binary-dir             - Display the binary dir for this preset\n"
	@printf "\n"
	@printf "  (alias: 'make silent' behaves the same as 'make quiet')\n"
	@printf "\n"
	@printf "Default target behavior:\n"
	@printf "  - In module directories: if EXECUTABLE=true -> build; else -> stage\n"
	@printf "  - In monorepo root (CWD == MONOREPO): run default in all modules listed in MODULES\n"

# Default target
default:
ifeq ($(MODE),monorepo)
	@printf "$(GREEN)Running default target in all modules: $(MODULES)$(NC)\n"
	@ret=0; \
	for mod in $(MODULES); do \
		if [ -d "$$mod" ]; then \
			printf "$(YELLOW)> $$mod: make (default)$(NC)\n"; \
			( cd "$$mod" && $(MAKE) ) || ret=1; \
		else \
			printf "$(YELLOW)Warning: Module $$mod does not exist, skipping$(NC)\n"; \
		fi; \
	done; \
	exit $$ret
else
ifeq ($(strip $(EXECUTABLE)),true)
	@printf "$(GREEN)EXECUTABLE=true: running build by default$(NC)\n"
	@$(MAKE) build
else
	@printf "$(GREEN)EXECUTABLE=false: running stage by default$(NC)\n"
	@$(MAKE) stage
endif
endif

#
# QUIET/NOISY targets
#
quiet:
	@if grep -q "^QUIET\s*:=\s*" .modules; then \
		sed -i 's/^QUIET\s*:=\s*.*/QUIET := true/' .modules; \
	else \
		echo "QUIET := true" >> .modules; \
	fi
	@printf "$(GREEN)Daily update check messages suppressed. Run 'make noisy' to re-enable.$(NC)\n"

silent: quiet

noisy:
	@if grep -q "^QUIET\s*:=\s*" .modules; then \
		sed -i 's/^QUIET\s*:=\s*.*/QUIET := false/' .modules; \
	else \
		echo "QUIET := false" >> .modules; \
	fi
	@printf "$(GREEN)Daily update check messages re-enabled.$(NC)\n"

#
# UPDATE target
#
update:
	@$(MAKE) __autoupdate FORCE=TRUE

check-update:
	@if [ -z "$(REPO)" ]; then \
		printf "$(RED)REPO not defined in .modules$(NC)\n"; \
		exit 1; \
	fi; \
	TMP_DIR=$$(mktemp -d /tmp/makefile.repo.XXXXXX); \
	if ! git clone --depth 1 "$(REPO)" "$$TMP_DIR" >/dev/null 2>&1; then \
		printf "$(RED)Failed to clone repo for update check.$(NC)\n"; \
		rm -rf "$$TMP_DIR"; \
		exit 1; \
	fi; \
	ONLINE_VERSION=$$($(MAKE) --no-print-directory -C "$$TMP_DIR" version 2>/dev/null); \
	rm -rf "$$TMP_DIR"; \
	if [ -z "$$ONLINE_VERSION" ]; then \
		printf "$(RED)Failed to obtain version from cloned repo.$(NC)\n"; \
		exit 1; \
	fi; \
	printf "\nUpdate Check Results\n"; \
	printf "--------------------\n"; \
	printf "Current Version : $(VERSION)\n"; \
	printf "On-line Version : $$ONLINE_VERSION\n"; \
	printf "   Last checked : $(LAST_CHECK_TIME)\n\n"

#
# CLEAN targets
#
clean:
ifeq ($(MODE),monorepo)
	@for mod in $(MODULES); do \
		printf "$(GREEN)Cleaning module: $$mod$(NC)\n"; \
		if [ -d "$$mod" ]; then \
			rm -rf "$$mod/build" "$$mod/out" "$$mod/external"; \
		else \
			printf "$(YELLOW)Warning: Module $$mod does not exist, skipping$(NC)\n"; \
		fi \
	done
	@printf "$(GREEN)Cleaning monorepo$(NC)\n"
	@rm -rf build out external
	@printf "$(GREEN)Removing staging directory: $(STAGEDIR)$(NC)\n"
	@rm -rf $(STAGEDIR)
else
	@printf "$(GREEN)Cleaning current module: $(CURRENT_DIR)$(NC)\n"
	@rm -rf build out external
endif

#
# CONFIG targets
#
config:
ifeq ($(MODE),monorepo)
	@printf "$(GREEN)Configuring all modules in MONOREPO $(MONOREPO)$(NC)\n"
	@for mod in $(MODULES); do \
		if [ -d "$$mod" ]; then \
			cd $$mod && $(MAKE) config || exit 1; \
			cd - >/dev/null; \
		else \
			printf "$(YELLOW)Warning: Module $$mod does not exist, skipping$(NC)\n"; \
		fi; \
	done
else
	@printf "$(GREEN)Configuring$(NC) current module: $(BOLD)$(CURRENT_DIR)$(NC) with preset $(GREEN)$(PRESET)$(NC)\n"
	@$(call run_config) || (printf "$(RED)Configure failed for $(CURRENT_DIR)$(NC)\n" && exit 1)
endif

define config_module
	@printf "$(GREEN)Configuring module: $(1) with preset $(BOLD)$(PRESET)$(NC)$(NC)\n"
	@if [ -d "$(MODULE_PREFIX)/$(1)" ]; then \
		cd $(MODULE_PREFIX)/$(1) && cmake --preset "$(PRESET)" || \
		(printf "$(RED)Configure failed for $(1)$(NC)\n" && exit 1); \
	else \
		printf "$(YELLOW)Warning: Module $(1) does not exist, skipping$(NC)\n"; \
	fi
endef

config-%:
	$(call validate_module,$*)
ifeq ($(MODE),monorepo)
ifeq ($*,All)
	@printf "$(GREEN)Configuring$(NC) all modules in MONOREPO $(BOLD)$(MONOREPO)$(NC)\n"
	@for mod in $(MODULES); do \
		if [ -d "$$mod" ]; then \
			cd $$mod && $(MAKE) config || exit 1; \
			cd - >/dev/null; \
		else \
			printf "$(YELLOW)Warning: Module $$mod does not exist, skipping$(NC)\n"; \
		fi; \
	done
else
	@printf "$(YELLOW)Delegating$(NC) to module $(BOLD)$*$(NC) for config...$(NC)\n"
	@if [ -d "$*" ]; then \
		cd $* && $(MAKE) config; \
	else \
		printf "$(RED)ERROR: Module $* does not exist$(NC)\n"; \
		exit 1; \
	fi
endif
else
ifeq ($*,All)
	@printf "$(GREEN)Configuring$(NC) all modules in dependency order$(NC)\n"
	@for mod in $(MODULES); do \
		$(MAKE) config_module_impl MODULE=$$mod || exit 1; \
	done
else
	$(call check_module_exists,$*)
	$(call config_module,$*)
endif
endif

config_module_impl:
	$(call config_module,$(MODULE))

#
# BUILD targets
#
build:
ifeq ($(MODE),monorepo)
	@printf "$(GREEN)Building$(NC) all modules in MONOREPO $(BOLD)$(MONOREPO)$(NC)\n"
	@for mod in $(MODULES); do \
		if [ -d "$$mod" ]; then \
			cd $$mod && $(MAKE) build || exit 1; \
			cd - >/dev/null; \
		else \
			printf "$(YELLOW)Warning: Module $$mod does not exist, skipping$(NC)\n"; \
		fi; \
	done
else
	@printf "$(GREEN)Building$(NC) current module: $(BOLD)$(CURRENT_DIR)$(NC) with preset $(BOLD)$(PRESET)$(NC)\n"
	@mkdir -p $(BINARY_DIR)
	@$(call run_build,) || (printf "$(RED)$(BOLD)Build failed for $(CURRENT_DIR)$(NC)\n" && exit 1)
endif

define build_module
	@printf "$(GREEN)Building$(NC) module: $(BOLD)$(1)$(NC) with preset $(BOLD)$(PRESET)$(NC)\n"
	@if [ -d "$(MODULE_PREFIX)/$(1)" ]; then \
		cd $(MODULE_PREFIX)/$(1) && cmake --build --preset "$(PRESET)" || \
		(printf "$(RED)Build failed for $(1)$(NC)\n" && exit 1); \
	else \
		printf "$(YELLOW)Warning: Module $(1) does not exist, skipping$(NC)\n"; \
	fi
endef

build-%:
	$(call validate_module,$*)
ifeq ($(MODE),monorepo)
ifeq ($*,All)
	@printf "$(GREEN)Building all modules in MONOREPO $(MONOREPO)$(NC)\n"
	@for mod in $(MODULES); do \
		if [ -d "$$mod" ]; then \
			cd $$mod && $(MAKE) build || exit 1; \
			cd - >/dev/null; \
		else \
			printf "$(YELLOW)Warning: Module $$mod does not exist, skipping$(NC)\n"; \
		fi; \
	done
else
	@printf "$(YELLOW)Delegating to module $* for build...$(NC)\n"
	@if [ -d "$*" ]; then \
		cd $* && $(MAKE) build; \
	else \
		printf "$(RED)ERROR: Module $* does not exist$(NC)\n"; \
		exit 1; \
	fi
endif
else
ifeq ($*,All)
	@printf "$(GREEN)Building all modules in dependency order$(NC)\n"
	@for mod in $(MODULES); do \
		$(MAKE) build_module_impl MODULE=$$mod || exit 1; \
	done
else
	$(call check_module_exists,$*)
	$(call build_module,$*)
endif
endif

build_module_impl:
	$(call build_module,$(MODULE))

#
# STAGE targets
#
stage:
ifeq ($(MODE),monorepo)
	@printf "$(GREEN)Staging all modules in MONOREPO $(MONOREPO)$(NC)\n"
	@for mod in $(MODULES); do \
		if [ -d "$$mod" ]; then \
			cd $$mod && $(MAKE) stage || exit 1; \
			cd - >/dev/null; \
		else \
			printf "$(YELLOW)Warning: Module $$mod does not exist, skipping$(NC)\n"; \
		fi; \
	done
else
ifeq ($(strip $(EXECUTABLE)),true)
	@printf "$(RED)ERROR: 'stage' is unavailable when EXECUTABLE=true$(NC)\n"; exit 1
else
	@printf "$(GREEN)Staging current module: $(CURRENT_DIR) to $(STAGEDIR)$(NC)\n"
	@mkdir -p $(STAGEDIR)
	@$(call run_build,--target install,$(STAGEDIR)) || \
		(printf "$(RED)Stage failed for $(CURRENT_DIR)$(NC)\n" && exit 1)
endif
endif

define stage_module
	@printf "$(GREEN)Staging module: $(1) to $(STAGEDIR)$(NC)\n"
	@if [ -d "$(MODULE_PREFIX)/$(1)" ]; then \
		if [ -f "$(MODULE_PREFIX)/$(1)/.modules" ] && \
		   grep -Eq '^[[:space:]]*EXECUTABLE[[:space:]]*:=[[:space:]]*true' "$(MODULE_PREFIX)/$(1)/.modules"; then \
			printf "$(RED)ERROR: 'stage' is unavailable for EXECUTABLE=true module: $(1)$(NC)\n"; exit 1; \
		fi; \
		mkdir -p $(STAGEDIR) && \
		cd $(MODULE_PREFIX)/$(1) && \
		DESTDIR=$(STAGEDIR) cmake --build --preset "$(PRESET)" --target install || \
		(printf "$(RED)Stage failed for $(1)$(NC)\n" && exit 1); \
	else \
		printf "$(YELLOW)Warning: Module $(1) does not exist, skipping$(NC)\n"; \
	fi
endef

stage-%:
	$(call validate_module,$*)
ifeq ($(MODE),monorepo)
ifeq ($*,All)
	@printf "$(GREEN)Staging all modules in MONOREPO $(MONOREPO)$(NC)\n"
	@for mod in $(MODULES); do \
		if [ -d "$$mod" ]; then \
			cd $$mod && $(MAKE) stage || exit 1; \
			cd - >/dev/null; \
		else \
			printf "$(YELLOW)Warning: Module $$mod does not exist, skipping$(NC)\n"; \
		fi; \
	done
else
	@printf "$(YELLOW)Delegating to module $* for stage...$(NC)\n"
	@if [ -d "$*" ]; then \
		cd $* && $(MAKE) stage; \
	else \
		printf "$(RED)ERROR: Module $* does not exist$(NC)\n"; \
		exit 1; \
	fi
endif
else
ifeq ($*,All)
	@printf "$(GREEN)Staging all modules in dependency order$(NC)\n"
	@for mod in $(MODULES); do \
		$(MAKE) stage_module_impl MODULE=$$mod || exit 1; \
	done
else
	$(call check_module_exists,$*)
	$(call stage_module,$*)
endif
endif

stage_module_impl:
	$(call stage_module,$(MODULE))

#
# INSTALL targets
#
install:
ifeq ($(MODE),monorepo)
	@printf "$(GREEN)Installing all modules in MONOREPO $(MONOREPO)$(NC)\n"
	@for mod in $(MODULES); do \
		if [ -d "$$mod" ]; then \
			cd $$mod && $(MAKE) install || exit 1; \
			cd - >/dev/null; \
		else \
			printf "$(YELLOW)Warning: Module $$mod does not exist, skipping$(NC)\n"; \
		fi; \
	done
else
ifeq ($(strip $(EXECUTABLE)),true)
	@printf "$(RED)ERROR: 'install' is unavailable when EXECUTABLE=true$(NC)\n"; exit 1
else
	@printf "$(GREEN)Installing current module: $(CURRENT_DIR) (requires sudo)$(NC)\n"
	@sudo cmake --build --preset "$(PRESET)" --target install || \
		(printf "$(RED)Install failed for $(CURRENT_DIR)$(NC)\n" && exit 1)
endif
endif

define install_module
	@printf "$(GREEN)Installing module: $(1) (requires sudo)$(NC)\n"
	@if [ -d "$(MODULE_PREFIX)/$(1)" ]; then \
		if [ -f "$(MODULE_PREFIX)/$(1)/.modules" ] && \
		   grep -Eq '^[[:space:]]*EXECUTABLE[[:space:]]*:=[[:space:]]*true' "$(MODULE_PREFIX)/$(1)/.modules"; then \
			printf "$(RED)ERROR: 'install' is unavailable for EXECUTABLE=true module: $(1)$(NC)\n"; exit 1; \
		fi; \
		cd $(MODULE_PREFIX)/$(1) && \
		sudo cmake --build --preset "$(PRESET)" --target install || \
		(printf "$(RED)Install failed for $(1)$(NC)\n" && exit 1); \
	else \
		printf "$(YELLOW)Warning: Module $(1) does not exist, skipping$(NC)\n"; \
	fi
endef

install-%:
	$(call validate_module,$*)
ifeq ($(MODE),monorepo)
ifeq ($*,All)
	@printf "$(GREEN)Installing all modules in MONOREPO $(MONOREPO)$(NC)\n"
	@for mod in $(MODULES); do \
		if [ -d "$$mod" ]; then \
			cd $$mod && $(MAKE) install || exit 1; \
			cd - >/dev/null; \
		else \
			printf "$(YELLOW)Warning: Module $$mod does not exist, skipping$(NC)\n"; \
		fi; \
	done
else
	@printf "$(YELLOW)Delegating to module $* for install...$(NC)\n"
	@if [ -d "$*" ]; then \
		cd $* && $(MAKE) install; \
	else \
		printf "$(RED)ERROR: Module $* does not exist$(NC)\n"; \
		exit 1; \
	fi
endif
else
ifeq ($*,All)
	@printf "$(GREEN)Installing all modules in dependency order$(NC)\n"
	@for mod in $(MODULES); do \
		$(MAKE) install_module_impl MODULE=$$mod || exit 1; \
	done
else
	$(call check_module_exists,$*)
	$(call install_module,$*)
endif
endif

install_module_impl:
	$(call install_module,$(MODULE))

#
# GIT PUSH targets
#
define git_push_repo
	printf "$(GREEN)Processing git push in: $$(pwd)$(NC)\n"; \
	if [ -d "cmake" ]; then \
		printf "$(GREEN)Processing cmake submodule...$(NC)\n"; \
		(cd cmake && \
		if ! git symbolic-ref -q HEAD >/dev/null 2>&1; then \
			printf "$(YELLOW)cmake submodule in detached HEAD, checking out master branch...$(NC)\n"; \
			if git checkout master 2>/dev/null || git checkout main 2>/dev/null; then \
				printf "$(GREEN)Checked out branch, pulling...$(NC)\n"; \
				git pull || (git merge --abort 2>/dev/null; printf "$(YELLOW)Pull failed$(NC)\n"); \
			else \
				printf "$(YELLOW)Could not checkout branch, skipping pull$(NC)\n"; \
			fi; \
		else \
			git pull || (git merge --abort 2>/dev/null; printf "$(YELLOW)Pull failed$(NC)\n"); \
		fi && \
		git add . && \
		(git diff --cached --quiet || (git commit -m "$(MSG)" && git push))); \
	fi; \
	git pull --no-recurse-submodules || (git merge --abort 2>/dev/null; printf "$(RED)Pull failed at $$(pwd)$(NC)\n"; exit 1); \
	git add . && \
	(git diff --cached --quiet || (git commit -m "$(MSG)" && git push))
endef

define sync_cmake_submodules
	printf "$(YELLOW)Syncing cmake submodules across all modules...$(NC)\n"
	for mod in $(MODULES); do \
		if [ -d "$(MODULE_PREFIX)/$$mod/cmake" ]; then \
			printf "$(GREEN)Syncing cmake in $$mod...$(NC)\n"; \
			(cd $(MODULE_PREFIX)/$$mod/cmake && \
			if ! git symbolic-ref -q HEAD >/dev/null 2>&1; then \
				printf "$(YELLOW)cmake in detached HEAD, checking out master branch...$(NC)\n"; \
				if git checkout master 2>/dev/null || git checkout main 2>/dev/null; then \
					printf "$(GREEN)Checked out branch, pulling...$(NC)\n"; \
					git pull || printf "$(YELLOW)Pull failed$(NC)\n"; \
				else \
					printf "$(YELLOW)Could not checkout branch, skipping pull$(NC)\n"; \
				fi; \
			else \
				git pull || printf "$(YELLOW)Pull failed$(NC)\n"; \
			fi); \
		fi; \
	done
endef

push:
ifeq ($(MODE),monorepo)
	@printf "$(YELLOW)At MONOREPO root ($(MONOREPO)). To push all modules and the monorepo, run: make push-All MSG=\"...\"$(NC)\n"
else
	@printf "$(GREEN)Pushing current module: $(CURRENT_DIR)$(NC)\n"
	@$(git_push_repo)
	@$(sync_cmake_submodules)
endif

push-All:
	@if [ -z "$(MONOREPO)" ] || [ "$(CURRENT_DIR)" != "$(MONOREPO)" ]; then \
		printf "$(RED)push-All can only be run from the root of a MONOREPO$(NC)\n"; \
		exit 1; \
	fi
	@printf "$(GREEN)Pushing all modules in MONOREPO $(MONOREPO)$(NC)\n"
	@for mod in $(MODULES); do \
		if [ -d "$$mod" ]; then \
			printf "$(GREEN)Pushing module: $$mod$(NC)\n"; \
			cd $$mod && { $(MAKE) pull; $(MAKE) push MSG="$(MSG)"; } || exit 1; \
			cd - >/dev/null; \
		else \
			printf "$(YELLOW)Warning: Module $$mod does not exist, skipping$(NC)\n"; \
		fi; \
	done
	@printf "$(GREEN)Pushing monorepo itself$(NC)\n"
	@$(git_push_repo)

push-%:
	$(call validate_module,$*)
ifeq ($(MODE),monorepo)
	@printf "$(YELLOW)Delegating to module $* for push, then pushing monorepo...$(NC)\n"
	@if [ -d "$*" ]; then \
		cd $* && $(MAKE) push MSG="$(MSG)"; \
	else \
		printf "$(RED)ERROR: Module $* does not exist$(NC)\n"; \
		exit 1; \
	fi
	@printf "$(GREEN)Pushing monorepo repo$(NC)\n"
	@$(git_push_repo)
else
	$(call check_module_exists,$*)
	@printf "$(GREEN)Pushing module: $*$(NC)\n"
	@cd $(MODULE_PREFIX)/$* && $(git_push_repo) || exit 1
	@$(sync_cmake_submodules)
endif

#
# GIT PULL targets
#
define git_pull_repo
	printf "$(GREEN)Processing git pull in: $$(pwd)$(NC)\n"; \
	git pull --no-recurse-submodules || (git merge --abort 2>/dev/null; printf "$(RED)Pull failed at $$(pwd)$(NC)\n"; exit 1); \
	if [ -d "cmake" ]; then \
		printf "$(GREEN)Pulling cmake submodule...$(NC)\n"; \
		cd cmake && \
		if ! git symbolic-ref -q HEAD >/dev/null; then \
			printf "$(YELLOW)cmake submodule in detached HEAD, checking out master branch...$(NC)\n"; \
			git checkout master 2>/dev/null || git checkout main 2>/dev/null || printf "$(YELLOW)Could not find master/main branch$(NC)\n"; \
		fi && \
		if git symbolic-ref -q HEAD >/dev/null; then \
			git pull || (git merge --abort 2>/dev/null; printf "$(RED)Pull failed in cmake submodule at $$(pwd)$(NC)\n"; exit 1); \
		else \
			printf "$(YELLOW)Skipping pull - cmake submodule still in detached HEAD$(NC)\n"; \
		fi && \
		cd ..; \
	fi
endef

pull-All:
	@if [ -z "$(MONOREPO)" ] || [ "$(CURRENT_DIR)" != "$(MONOREPO)" ]; then \
		printf "$(RED)pull-All can only be run from the root of a MONOREPO$(NC)\n"; \
		exit 1; \
	fi
	@printf "$(GREEN)Pulling all modules in MONOREPO $(MONOREPO)$(NC)\n"
	@for mod in $(MODULES); do \
		if [ -d "$$mod" ]; then \
			printf "$(GREEN)Pulling module: $$mod$(NC)\n"; \
			cd $$mod && $(MAKE) update && $(MAKE) pull || exit 1; \
			cd - >/dev/null; \
		else \
			printf "$(YELLOW)Warning: Module $$mod does not exist, skipping$(NC)\n"; \
		fi; \
	done
	@printf "$(GREEN)Pulling monorepo repo$(NC)\n"
	@$(git_pull_repo)

pull:
ifeq ($(MODE),monorepo)
	@printf "$(YELLOW)Running pull-All from monorepo root...$(NC)\n"
	@$(MAKE) pull-All
else
	@printf "$(GREEN)Pulling current module: $(CURRENT_DIR)$(NC)\n"
	@$(git_pull_repo)
endif

pull-%:
	$(call validate_module,$*)
ifeq ($(MODE),monorepo)
ifeq ($*,All)
	@printf "$(YELLOW)Running pull-All from monorepo root...$(NC)\n"
	@$(MAKE) pull-All
else
	@printf "$(YELLOW)Delegating to module $* for pull, then pulling monorepo...$(NC)\n"
	@if [ -d "$*" ]; then \
		cd $* && $(MAKE) pull; \
	else \
		printf "$(RED)ERROR: Module $* does not exist$(NC)\n"; \
		exit 1; \
	fi
	@printf "$(GREEN)Pulling monorepo repo$(NC)\n"
	@$(git_pull_repo)
endif
else
ifeq ($*,All)
	@printf "$(GREEN)Pulling all modules$(NC)\n"
	@for mod in $(MODULES); do \
		if [ -d "$(MODULE_PREFIX)/$$mod" ]; then \
			printf "$(GREEN)Pulling module: $$mod$(NC)\n"; \
			cd $(MODULE_PREFIX)/$$mod && $(MAKE) pull && cd - >/dev/null || exit 1; \
		else \
			printf "$(YELLOW)Warning: Module $$mod does not exist, skipping$(NC)\n"; \
		fi; \
	done
else
	$(call check_module_exists,$*)
	@printf "$(GREEN)Pulling module: $*$(NC)\n"
	@cd $(MODULE_PREFIX)/$* && $(git_pull_repo) || exit 1
endif
endif

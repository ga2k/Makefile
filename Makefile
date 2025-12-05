# Makefile for multi-module CMake project with superbuild support
# Requires .modules configuration file

.PHONY: help clean config build stage install push pull update silent quiet noisy __autoupdate
# Keep autoupdate quiet to avoid leaking its shell script when make echoes commands
.SILENT: __autoupdate
.DEFAULT_GOAL := help

# Auto-update implementation
# This runs once at the start of any requested target (except update/quiet/silent/noisy),
# checks the remote Makefile, and if an update is available it replaces this
# Makefile and aborts the current run with a message to re-run. If up-to-date,
# it optionally prints a message (suppressed by the 'silent' marker).

# Variables used by update/quiet(silent) targets
MAKEFILE_UPDATE_MARKER := .makefile_update_check
MAKEFILE_SILENT_MARKER := .makefile_silent
MAKEFILE_REPO_URL := https://raw.githubusercontent.com/ga2k/Makefile/master/Makefile
TODAY := $(shell date +%Y-%m-%d)

# Color output (use -e with echo for these to work)
RED := \033[0;31m
GREEN := \033[0;32m
YELLOW := \033[1;33m
NC := \033[0m # No Color

# Export MSG and PRESET for recursive make calls
export MSG
export PRESET

# Ensure auto-update runs before the user's goals (skip for update/silent/noisy)
AUTOUPDATE_SKIP_GOALS := update quiet silent noisy
ifneq ($(strip $(MAKECMDGOALS)),)
  ifeq (,$(filter $(AUTOUPDATE_SKIP_GOALS),$(MAKECMDGOALS)))
    $(foreach g,$(MAKECMDGOALS),$(eval $(g): __autoupdate))
  endif
endif

__autoupdate:
	@IS_SILENT=0; [ -f "$(MAKEFILE_SILENT_MARKER)" ] && IS_SILENT=1; \
	TODAY="$(TODAY)"; \
	LAST=""; [ -f "$(MAKEFILE_UPDATE_MARKER)" ] && LAST=$$(cat $(MAKEFILE_UPDATE_MARKER) 2>/dev/null); \
	if [ "$$LAST" = "$$TODAY" ]; then \
		if [ "$$IS_SILENT" -ne 1 ]; then \
			echo -e "Checking for update: $(GREEN)already done today.$(NC)"; \
			echo ""; \
			echo -e "Run '$(YELLOW)make update$(NC)' to update anyway."; \
			echo -e "Run '$(YELLOW)make quiet$(NC)'  to stop these messages."; \
			echo -e "Run '$(YELLOW)make noisy$(NC)'  to start showing them again."; \
			echo; \
		fi; \
		exit 0; \
	fi; \
	\
	if ! command -v curl >/dev/null 2>&1; then \
		echo "$$TODAY" > $(MAKEFILE_UPDATE_MARKER); \
		echo -e "Checking for update: $(GREEN)your file is up-to-date.$(NC) Checking again tomorrow."; \
		exit 0; \
	fi; \
	TMP_BODY=$$(mktemp /tmp/makefile.remote.XXXXXX); \
	TMP_HEAD=$$(mktemp /tmp/makefile.headers.XXXXXX); \
	if ! curl -fsSL -D $$TMP_HEAD -o $$TMP_BODY "$(MAKEFILE_REPO_URL)" >/dev/null 2>&1; then \
		echo "$$TODAY" > $(MAKEFILE_UPDATE_MARKER); \
		rm -f $$TMP_BODY $$TMP_HEAD; \
		echo -e "Checking for update: $(GREEN)your file is up-to-date.$(NC) Checking again tomorrow."; \
		exit 0; \
	fi; \
	if cmp -s $$TMP_BODY Makefile; then \
		rm -f $$TMP_BODY $$TMP_HEAD; \
		echo "$$TODAY" > $(MAKEFILE_UPDATE_MARKER); \
		echo -e "Checking for update: $(GREEN)your file is up-to-date.$(NC) Checking again tomorrow."; \
		exit 0; \
	fi; \
	\
	IS_DIRTY=1; \
	if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then \
		if git ls-files --error-unmatch Makefile >/dev/null 2>&1; then \
			if git diff --quiet -- Makefile && git diff --quiet --cached -- Makefile; then IS_DIRTY=0; fi; \
		fi; \
	else \
		IS_DIRTY=1; \
	fi; \
	LOCAL_EPOCH=$$(stat -c %Y Makefile 2>/dev/null || stat -f %m Makefile 2>/dev/null || echo 0); \
	REM_LM=$$(grep -i '^Last-Modified:' $$TMP_HEAD | sed 's/^[^:]*:\s*//'); \
	if [ -n "$$REM_LM" ]; then \
		REM_EPOCH=$$(date -u -d "$$REM_LM" +%s 2>/dev/null || date -u -j -f '%a, %d %b %Y %H:%M:%S %Z' "$$REM_LM" +%s 2>/dev/null || echo 0); \
	else \
		REM_EPOCH=0; \
	fi; \
	\
	SHOULD_REPLACE=1; \
	if [ "$$IS_DIRTY" -ne 0 ]; then SHOULD_REPLACE=0; fi; \
	if [ "$$SHOULD_REPLACE" -eq 1 ]; then \
		[ -z "$$UPDATE_DEBUG" ] || echo -e "$(YELLOW)[autoupdate debug] replacing (dirty=$$IS_DIRTY, trust_ts=$$UPDATE_TRUST_TIMESTAMP, remote=$$REM_EPOCH, local=$$LOCAL_EPOCH)$(NC)"; \
		mv -f $$TMP_BODY Makefile; \
		rm -f $$TMP_HEAD; \
		echo "$$TODAY" > $(MAKEFILE_UPDATE_MARKER); \
		echo -e "Checking for update: $(GREEN)a newer file found and downloaded.$(NC) Please re-run your command"; \
		exit 2; \
	else \
		[ -z "$$UPDATE_DEBUG" ] || { \
			LHS=$$(sha256sum Makefile 2>/dev/null | awk '{print $$1}'); \
			RHS=$$(sha256sum $$TMP_BODY 2>/dev/null | awk '{print $$1}'); \
			printf "$(YELLOW)[autoupdate debug] url=%s\nlocal_epoch=%s remote_epoch=%s\nlocal_sha256=%s\nremote_sha256=%s\n(reason: %s)$(NC)\n" "$(MAKEFILE_REPO_URL)" "$$LOCAL_EPOCH" "$$REM_EPOCH" "$$LHS" "$$RHS" "$$( [ "$$IS_DIRTY" -ne 0 ] && echo dirty || ( [ "$$UPDATE_TRUST_TIMESTAMP" = "1" ] && [ "$$REM_EPOCH" -lt "$$LOCAL_EPOCH" ] && echo remote_older || echo other ))"; \
		}; \
		rm -f $$TMP_BODY $$TMP_HEAD; \
		echo "$$TODAY" > $(MAKEFILE_UPDATE_MARKER); \
		echo -e "Checking for update: $(RED)your local Makefile has uncommitted changes; not replacing.$(NC) Set UPDATE_FORCE=1 to force."; \
		exit 0; \
	fi

# Check for .modules file
ifeq (,$(wildcard ./.modules))
$(error $(RED)ERROR: .modules file not found in current directory$(NC))
endif

# Parse .modules file
MONOREPO := $(shell grep -E '^MONOREPO\s*:=' .modules 2>/dev/null | sed 's/.*:=\s*\([^ \t#]*\).*/\1/')
MODULES := $(shell grep -E '^MODULES\s*:=' .modules 2>/dev/null | sed 's/.*:=\s*\([^#]*\).*/\1/')
STAGEDIR := $(shell grep -E '^STAGEDIR\s*:=' .modules 2>/dev/null | sed 's/.*:=\s*\([^ \t#]*\).*/\1/')
PRESET_FILE := $(shell grep -E '^PRESET\s*:=' .modules 2>/dev/null | sed 's/.*:=\s*\(.*\)/\1/' | sed 's/^"\(.*\)"$$/\1/' | sed "s/^'\(.*\)'$$/\1/" | sed 's/[ \t]*#.*//' | sed 's/[ \t]*$$//')

# Set defaults
STAGEDIR := $(if $(STAGEDIR),$(STAGEDIR),~/dev/stage)
PRESET := $(if $(PRESET),$(PRESET),$(if $(PRESET_FILE),$(PRESET_FILE),default))

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
MSG ?= auto-commit $(DATE)

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
ifneq (,$(wildcard CMakePresets.in))
ifneq (,$(wildcard cmake/filter-presets.py))
$(shell python3 cmake/filter-presets.py CMakePresets.in CMakePresets.json)
$(info Generated CMakePresets.json from CMakePresets.in)
endif
endif
endif

# Helper: configure with preset when CMakePresets.json exists
define run_config
	@if [ -f CMakePresets.json ]; then \
		echo -e "$(GREEN)Configuring with preset $(PRESET)$(NC)"; \
		cmake --preset "$(PRESET)"; \
	else \
		echo -e "$(GREEN)Configuring in $(BUILD_DIR)$(NC)"; \
		cmake -S . -B $(BUILD_DIR); \
	fi
endef

# Helper: build with preset when CMakePresets.json exists; otherwise configure and build in $(BUILD_DIR)
# Usage: $(call run_build,<cmake-args>,<destdir>)
# If destdir is provided, it will be set as DESTDIR environment variable
# Auto-configures if build directory doesn't exist
define run_build
	@if [ -f CMakePresets.json ]; then \
		if ! cmake --build --preset "$(PRESET)" --target help >/dev/null 2>&1; then \
			echo -e "$(YELLOW)Build cache not found, configuring first...$(NC)"; \
			cmake --preset "$(PRESET)" || exit 1; \
		fi; \
		$(if $(2),DESTDIR=$(2)) cmake --build --preset "$(PRESET)" $(1); \
	else \
		if [ ! -f "$(BUILD_DIR)/CMakeCache.txt" ]; then \
			echo -e "$(YELLOW)Build cache not found, configuring first...$(NC)"; \
			cmake -S . -B $(BUILD_DIR) || exit 1; \
		fi; \
		$(if $(2),DESTDIR=$(2)) cmake --build $(BUILD_DIR) $(1); \
	fi
endef

help:
	@echo -e "$(GREEN)Multi-Module CMake Build System$(NC)"
	@echo "Mode: $(MODE)"
	@echo "Modules: $(MODULES)"
	@echo "Stage Dir: $(STAGEDIR)"
	@echo "Preset: $(PRESET)"
	@echo ""
	@echo "Available targets:"
	@echo "  make clean                  - Clean current module"
	@echo "  make config                 - Configure current module"
	@echo "  make build                  - Build current module (auto-configures if needed)"
	@echo "  make stage                  - Stage current module to STAGEDIR"
	@echo "  make install                - Install current module (requires sudo)"
	@echo "  make clean-<Module|All>     - Clean specific module or all"
	@echo "  make config-<Module|All>    - Configure specific module or all"
	@echo "  make build-<Module|All>     - Build specific module or all"
	@echo "  make stage-<Module|All>     - Stage specific module or all"
	@echo "  make install-<Module|All>   - Install specific module or all"
	@echo "  make push [MSG=\"msg\"]       - Commit and push current module"
	@echo "  make push-<Module|All>      - Commit and push specific module or all"
	@echo "  make pull                   - Pull current module"
	@echo "  make pull-<Module|All>      - Pull specific module or all"
	@echo "  make update                 - Force update Makefile from repository"
	@echo "  make quiet                  - Suppress daily update check messages"
	@echo "  make noisy                  - Re-enable daily update check messages"
	@echo "  (alias: 'make silent' behaves the same as 'make quiet')"

#
# QUIET/NOISY targets ("silent" kept as alias)
#
quiet:
	@touch $(MAKEFILE_SILENT_MARKER)
	@echo -e "$(GREEN)Daily update check messages suppressed. Run 'make noisy' to re-enable.$(NC)"

silent: quiet

noisy:
	@rm -f $(MAKEFILE_SILENT_MARKER)
	@echo -e "$(GREEN)Daily update check messages re-enabled.$(NC)"

#
# UPDATE target
#
update:
	@printf "Checking for update: "
	@if command -v curl >/dev/null 2>&1; then \
		TMP_BODY=$$(mktemp /tmp/makefile.remote.XXXXXX); \
		TMP_HEAD=$$(mktemp /tmp/makefile.headers.XXXXXX); \
		if ! curl -fsSL -D $$TMP_HEAD -o $$TMP_BODY "$(MAKEFILE_REPO_URL)" >/dev/null 2>&1; then \
			rm -f $$TMP_BODY $$TMP_HEAD; \
			echo -e "$(RED)ERROR: failed to download remote Makefile.$(NC)"; \
			exit 1; \
		fi; \
		if cmp -s $$TMP_BODY Makefile; then \
			rm -f $$TMP_BODY $$TMP_HEAD; \
			echo -e "$(GREEN)you have the newest version.$(NC)"; \
			exit 0; \
		fi; \
		# gather local/remote metadata \
		LOCAL_EPOCH=$$(stat -c %Y Makefile 2>/dev/null || stat -f %m Makefile 2>/dev/null || echo 0); \
		REM_LM=$$(grep -i '^Last-Modified:' $$TMP_HEAD | sed 's/^[^:]*:\s*//'); \
		if [ -n "$$REM_LM" ]; then \
			REM_EPOCH=$$(date -u -d "$$REM_LM" +%s 2>/dev/null || date -u -j -f '%a, %d %b %Y %H:%M:%S %Z' "$$REM_LM" +%s 2>/dev/null || echo 0); \
		else \
			REM_EPOCH=0; \
		fi; \
		# refuse overwrite if local Makefile has uncommitted changes unless forced \
		IS_DIRTY=0; \
		if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1 && git ls-files --error-unmatch Makefile >/dev/null 2>&1; then \
			if ! (git diff --quiet -- Makefile && git diff --quiet --cached -- Makefile); then IS_DIRTY=1; fi; \
		fi; \
		if [ "$$IS_DIRTY" -eq 1 ] && [ "$$UPDATE_FORCE" != "1" ]; then \
			rm -f $$TMP_BODY $$TMP_HEAD; \
			echo -e "$(RED)your local Makefile has uncommitted changes; not replacing.$(NC) Set UPDATE_FORCE=1 to force.$(NC)"; \
			exit 0; \
		fi; \
		if [ "$$UPDATE_TRUST_TIMESTAMP" = "1" ] && [ "$$REM_EPOCH" -lt "$$LOCAL_EPOCH" ] && [ "$$UPDATE_FORCE" != "1" ]; then \
			rm -f $$TMP_BODY $$TMP_HEAD; \
			echo -e "$(YELLOW)remote Last-Modified is older than local mtime; not replacing due to UPDATE_TRUST_TIMESTAMP=1. Set UPDATE_FORCE=1 to force or unset UPDATE_TRUST_TIMESTAMP.$(NC)"; \
			exit 0; \
		fi; \
		if [ -n "$$UPDATE_DEBUG" ]; then \
			LHS=$$(sha256sum Makefile 2>/dev/null | awk '{print $$1}'); \
			RHS=$$(sha256sum $$TMP_BODY 2>/dev/null | awk '{print $$1}'); \
			printf "[update debug]\n  url=%s\n  local_epoch=%s\n  remote_last_modified=%s\n  remote_epoch=%s\n  local_sha256=%s\n  remote_sha256=%s\n" "$(MAKEFILE_REPO_URL)" "$$LOCAL_EPOCH" "$$REM_LM" "$$REM_EPOCH" "$$LHS" "$$RHS"; \
		fi; \
		mv -f $$TMP_BODY Makefile; \
		rm -f $$TMP_HEAD; \
		echo "$(TODAY)" > $(MAKEFILE_UPDATE_MARKER); \
		echo -e "$(GREEN)your version was updated. Please re-run your make command.$(NC)"; \
	else \
		echo -e "$(RED)ERROR: curl not found. Cannot update Makefile.$(NC)"; \
		exit 1; \
	fi

#
# CLEAN targets
#
clean:
ifeq ($(MODE),monorepo)
	@echo -e "$(YELLOW)Delegating to first module for clean-All...$(NC)"
	@cd $(word 1,$(MODULES)) && $(MAKE) clean-All
else
	@echo -e "$(GREEN)Cleaning current module: $(CURRENT_DIR)$(NC)"
	@rm -rf build out
endif

define clean_module
	@echo -e "$(GREEN)Cleaning module: $(1)$(NC)"
	@if [ -d "$(MODULE_PREFIX)/$(1)" ]; then \
		cd $(MODULE_PREFIX)/$(1) && rm -rf build out; \
	else \
		echo -e "$(YELLOW)Warning: Module $(1) does not exist, skipping$(NC)"; \
	fi
endef

clean-%:
	$(call validate_module,$*)
ifeq ($(MODE),monorepo)
ifeq ($*,All)
	@echo -e "$(YELLOW)Delegating to first module for clean-All...$(NC)"
	@cd $(word 1,$(MODULES)) && $(MAKE) clean-All
else
	@echo -e "$(YELLOW)Delegating to module $* for clean...$(NC)"
	@if [ -d "$*" ]; then \
		cd $* && $(MAKE) clean; \
	else \
		echo -e "$(RED)ERROR: Module $* does not exist$(NC)"; \
		exit 1; \
	fi
endif
else
ifeq ($*,All)
	@echo -e "$(GREEN)Cleaning all modules$(NC)"
	@for mod in $(MODULES); do \
		$(MAKE) clean_module_impl MODULE=$$mod; \
	done
	@echo -e "$(GREEN)Removing staging directory: $(STAGEDIR)$(NC)"
	@rm -rf $(STAGEDIR)
else
	$(call check_module_exists,$*)
	$(call clean_module,$*)
endif
endif

clean_module_impl:
	$(call clean_module,$(MODULE))

#
# CONFIG targets
#
config:
ifeq ($(MODE),monorepo)
	@echo -e "$(YELLOW)Delegating to first module for config-All...$(NC)"
	@cd $(word 1,$(MODULES)) && $(MAKE) config-All
else
	@echo -e "$(GREEN)Configuring current module: $(CURRENT_DIR) with preset $(PRESET)$(NC)"
	@$(call run_config) || (echo -e "$(RED)Configure failed for $(CURRENT_DIR)$(NC)" && exit 1)
endif

define config_module
	@echo -e "$(GREEN)Configuring module: $(1) with preset $(PRESET)$(NC)"
	@if [ -d "$(MODULE_PREFIX)/$(1)" ]; then \
		cd $(MODULE_PREFIX)/$(1) && cmake --preset "$(PRESET)" || \
		(echo -e "$(RED)Configure failed for $(1)$(NC)" && exit 1); \
	else \
		echo -e "$(YELLOW)Warning: Module $(1) does not exist, skipping$(NC)"; \
	fi
endef

config-%:
	$(call validate_module,$*)
ifeq ($(MODE),monorepo)
ifeq ($*,All)
	@echo -e "$(YELLOW)Delegating to first module for config-All...$(NC)"
	@cd $(word 1,$(MODULES)) && $(MAKE) config-All
else
	@echo -e "$(YELLOW)Delegating to module $* for config...$(NC)"
	@if [ -d "$*" ]; then \
		cd $* && $(MAKE) config; \
	else \
		echo -e "$(RED)ERROR: Module $* does not exist$(NC)"; \
		exit 1; \
	fi
endif
else
ifeq ($*,All)
	@echo -e "$(GREEN)Configuring all modules in dependency order$(NC)"
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
	@echo -e "$(YELLOW)Delegating to first module for build-All...$(NC)"
	@cd $(word 1,$(MODULES)) && $(MAKE) build-All
else
	@echo -e "$(GREEN)Building current module: $(CURRENT_DIR) with preset $(PRESET)$(NC)"
	@mkdir -p build/debug/shared
	@$(call run_build,) || (echo -e "$(RED)Build failed for $(CURRENT_DIR)$(NC)" && exit 1)
endif

define build_module
	@echo -e "$(GREEN)Building module: $(1) with preset $(PRESET)$(NC)"
	@if [ -d "$(MODULE_PREFIX)/$(1)" ]; then \
		cd $(MODULE_PREFIX)/$(1) && cmake --build --preset "$(PRESET)" || \
		(echo -e "$(RED)Build failed for $(1)$(NC)" && exit 1); \
	else \
		echo -e "$(YELLOW)Warning: Module $(1) does not exist, skipping$(NC)"; \
	fi
endef

build-%:
	$(call validate_module,$*)
ifeq ($(MODE),monorepo)
ifeq ($*,All)
	@echo -e "$(YELLOW)Delegating to first module for build-All...$(NC)"
	@cd $(word 1,$(MODULES)) && $(MAKE) build-All
else
	@echo -e "$(YELLOW)Delegating to module $* for build...$(NC)"
	@if [ -d "$*" ]; then \
		cd $* && $(MAKE) build; \
	else \
		echo -e "$(RED)ERROR: Module $* does not exist$(NC)"; \
		exit 1; \
	fi
endif
else
ifeq ($*,All)
	@echo -e "$(GREEN)Building all modules in dependency order$(NC)"
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
	@echo -e "$(YELLOW)Delegating to first module for stage-All...$(NC)"
	@cd $(word 1,$(MODULES)) && $(MAKE) stage-All
else
	@echo -e "$(GREEN)Staging current module: $(CURRENT_DIR) to $(STAGEDIR)/$(CURRENT_DIR)$(NC)"
	@mkdir -p $(STAGEDIR)/$(CURRENT_DIR)
	@mkdir -p build/debug/shared
	@$(call run_build,--target install,$(STAGEDIR)/$(CURRENT_DIR)) || \
		(echo -e "$(RED)Stage failed for $(CURRENT_DIR)$(NC)" && exit 1)
endif

define stage_module
	@echo -e "$(GREEN)Staging module: $(1) to $(STAGEDIR)/$(1)$(NC)"
	@if [ -d "$(MODULE_PREFIX)/$(1)" ]; then \
		mkdir -p $(STAGEDIR)/$(1) && \
		cd $(MODULE_PREFIX)/$(1) && \
		DESTDIR=$(STAGEDIR)/$(1) cmake --build --preset "$(PRESET)" --target install || \
		(echo -e "$(RED)Stage failed for $(1)$(NC)" && exit 1); \
	else \
		echo -e "$(YELLOW)Warning: Module $(1) does not exist, skipping$(NC)"; \
	fi
endef

stage-%:
	$(call validate_module,$*)
ifeq ($(MODE),monorepo)
ifeq ($*,All)
	@echo -e "$(YELLOW)Delegating to first module for stage-All...$(NC)"
	@cd $(word 1,$(MODULES)) && $(MAKE) stage-All
else
	@echo -e "$(YELLOW)Delegating to module $* for stage...$(NC)"
	@if [ -d "$*" ]; then \
		cd $* && $(MAKE) stage; \
	else \
		echo -e "$(RED)ERROR: Module $* does not exist$(NC)"; \
		exit 1; \
	fi
endif
else
ifeq ($*,All)
	@echo -e "$(GREEN)Staging all modules in dependency order$(NC)"
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
	@echo -e "$(YELLOW)Delegating to first module for install-All...$(NC)"
	@cd $(word 1,$(MODULES)) && $(MAKE) install-All
else
	@echo -e "$(GREEN)Installing current module: $(CURRENT_DIR) (requires sudo)$(NC)"
	@sudo cmake --build --preset "$(PRESET)" --target install || \
		(echo -e "$(RED)Install failed for $(CURRENT_DIR)$(NC)" && exit 1)
endif

define install_module
	@echo -e "$(GREEN)Installing module: $(1) (requires sudo)$(NC)"
	@if [ -d "$(MODULE_PREFIX)/$(1)" ]; then \
		cd $(MODULE_PREFIX)/$(1) && \
		sudo cmake --build --preset "$(PRESET)" --target install || \
		(echo -e "$(RED)Install failed for $(1)$(NC)" && exit 1); \
	else \
		echo -e "$(YELLOW)Warning: Module $(1) does not exist, skipping$(NC)"; \
	fi
endef

install-%:
	$(call validate_module,$*)
ifeq ($(MODE),monorepo)
ifeq ($*,All)
	@echo -e "$(YELLOW)Delegating to first module for install-All...$(NC)"
	@cd $(word 1,$(MODULES)) && $(MAKE) install-All
else
	@echo -e "$(YELLOW)Delegating to module $* for install...$(NC)"
	@if [ -d "$*" ]; then \
		cd $* && $(MAKE) install; \
	else \
		echo -e "$(RED)ERROR: Module $* does not exist$(NC)"; \
		exit 1; \
	fi
endif
else
ifeq ($*,All)
	@echo -e "$(GREEN)Installing all modules in dependency order$(NC)"
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
	echo -e "$(GREEN)Processing git push in: $$(pwd)$(NC)"; \
	if [ -d "cmake" ]; then \
		echo -e "$(GREEN)Processing cmake submodule...$(NC)"; \
		(cd cmake && \
		if ! git symbolic-ref -q HEAD >/dev/null 2>&1; then \
			echo -e "$(YELLOW)cmake submodule in detached HEAD, checking out master branch...$(NC)"; \
			if git checkout master 2>/dev/null || git checkout main 2>/dev/null; then \
				echo -e "$(GREEN)Checked out branch, pulling...$(NC)"; \
				git pull || (git merge --abort 2>/dev/null; echo -e "$(YELLOW)Pull failed$(NC)"); \
			else \
				echo -e "$(YELLOW)Could not checkout branch, skipping pull$(NC)"; \
			fi; \
		else \
			git pull || (git merge --abort 2>/dev/null; echo -e "$(YELLOW)Pull failed$(NC)"); \
		fi && \
		git add . && \
		(git diff --cached --quiet || (git commit -m "$(MSG)" && git push))); \
	fi; \
	git pull --no-recurse-submodules || (git merge --abort 2>/dev/null; echo -e "$(RED)Pull failed at $$(pwd)$(NC)"; exit 1); \
	git add . && \
	(git diff --cached --quiet || (git commit -m "$(MSG)" && git push))
endef

define sync_cmake_submodules
	echo -e "$(YELLOW)Syncing cmake submodules across all modules...$(NC)"
	for mod in $(MODULES); do \
		if [ -d "$(MODULE_PREFIX)/$$mod/cmake" ]; then \
			echo -e "$(GREEN)Syncing cmake in $$mod...$(NC)"; \
			(cd $(MODULE_PREFIX)/$$mod/cmake && \
			if ! git symbolic-ref -q HEAD >/dev/null 2>&1; then \
				echo -e "$(YELLOW)cmake in detached HEAD, checking out master branch...$(NC)"; \
				if git checkout master 2>/dev/null || git checkout main 2>/dev/null; then \
					echo -e "$(GREEN)Checked out branch, pulling...$(NC)"; \
					git pull || echo -e "$(YELLOW)Pull failed$(NC)"; \
				else \
					echo -e "$(YELLOW)Could not checkout branch, skipping pull$(NC)"; \
				fi; \
			else \
				git pull || echo -e "$(YELLOW)Pull failed$(NC)"; \
			fi); \
		fi; \
	done
endef

push:
ifeq ($(MODE),monorepo)
	@echo -e "$(YELLOW)At MONOREPO root ($(MONOREPO)). To push all modules and the monorepo, run: make push-All MSG=\"...\"$(NC)"
else
	@echo -e "$(GREEN)Pushing current module: $(CURRENT_DIR)$(NC)"
	@$(git_push_repo)
	@$(sync_cmake_submodules)
endif

push-All:
	@if [ -z "$(MONOREPO)" ] || [ "$(CURRENT_DIR)" != "$(MONOREPO)" ]; then \
		echo -e "$(RED)push-All can only be run from the root of a MONOREPO$(NC)"; \
		exit 1; \
	fi
	@echo -e "$(GREEN)Pushing all modules in MONOREPO $(MONOREPO)$(NC)"
	@for mod in $(MODULES); do \
		if [ -d "$$mod" ]; then \
			echo -e "$(GREEN)Pushing module: $$mod$(NC)"; \
			cd $$mod && $(MAKE) push MSG="$(MSG)" || exit 1; \
			cd - >/dev/null; \
		else \
			echo -e "$(YELLOW)Warning: Module $$mod does not exist, skipping$(NC)"; \
		fi; \
	done
	@echo -e "$(GREEN)Pushing monorepo itself$(NC)"
	@$(git_push_repo)

push-%:
	$(call validate_module,$*)
ifeq ($(MODE),monorepo)
	@echo -e "$(YELLOW)Delegating to module $* for push, then pushing monorepo...$(NC)"
	@if [ -d "$*" ]; then \
		cd $* && $(MAKE) push MSG="$(MSG)"; \
	else \
		echo -e "$(RED)ERROR: Module $* does not exist$(NC)"; \
		exit 1; \
	fi
	@echo -e "$(GREEN)Pushing monorepo repo$(NC)"
	@$(git_push_repo)
else
	$(call check_module_exists,$*)
	@echo -e "$(GREEN)Pushing module: $*$(NC)"
	@cd $(MODULE_PREFIX)/$* && $(git_push_repo) || exit 1
	@$(sync_cmake_submodules)
endif

#
# GIT PULL targets
#
define git_pull_repo
	echo -e "$(GREEN)Processing git pull in: $$(pwd)$(NC)"; \
	git pull --no-recurse-submodules || (git merge --abort 2>/dev/null; echo -e "$(RED)Pull failed at $$(pwd)$(NC)"; exit 1); \
	if [ -d "cmake" ]; then \
		echo -e "$(GREEN)Pulling cmake submodule...$(NC)"; \
		cd cmake && \
		if ! git symbolic-ref -q HEAD >/dev/null; then \
			echo -e "$(YELLOW)cmake submodule in detached HEAD, checking out master branch...$(NC)"; \
			git checkout master 2>/dev/null || git checkout main 2>/dev/null || echo -e "$(YELLOW)Could not find master/main branch$(NC)"; \
		fi && \
		if git symbolic-ref -q HEAD >/dev/null; then \
			git pull || (git merge --abort 2>/dev/null; echo -e "$(RED)Pull failed in cmake submodule at $$(pwd)$(NC)"; exit 1); \
		else \
			echo -e "$(YELLOW)Skipping pull - cmake submodule still in detached HEAD$(NC)"; \
		fi && \
		cd ..; \
	fi
endef

pull-All:
	@if [ -z "$(MONOREPO)" ] || [ "$(CURRENT_DIR)" != "$(MONOREPO)" ]; then \
		echo -e "$(RED)pull-All can only be run from the root of a MONOREPO$(NC)"; \
		exit 1; \
	fi
	@echo -e "$(GREEN)Pulling all modules in MONOREPO $(MONOREPO)$(NC)"
	@for mod in $(MODULES); do \
		if [ -d "$$mod" ]; then \
			echo -e "$(GREEN)Pulling module: $$mod$(NC)"; \
			cd $$mod && $(MAKE) update && $(MAKE) pull || exit 1; \
			cd - >/dev/null; \
		else \
			echo -e "$(YELLOW)Warning: Module $$mod does not exist, skipping$(NC)"; \
		fi; \
	done
	@echo -e "$(GREEN)Pulling monorepo repo$(NC)"
	@$(git_pull_repo)

pull:
ifeq ($(MODE),monorepo)
	@echo -e "$(YELLOW)Running pull-All from monorepo root...$(NC)"
	@$(MAKE) pull-All
else
	@echo -e "$(GREEN)Pulling current module: $(CURRENT_DIR)$(NC)"
	@$(git_pull_repo)
endif

pull-%:
	$(call validate_module,$*)
ifeq ($(MODE),monorepo)
ifeq ($*,All)
	@echo -e "$(YELLOW)Running pull-All from monorepo root...$(NC)"
	@$(MAKE) pull-All
else
	@echo -e "$(YELLOW)Delegating to module $* for pull, then pulling monorepo...$(NC)"
	@if [ -d "$*" ]; then \
		cd $* && $(MAKE) pull; \
	else \
		echo -e "$(RED)ERROR: Module $* does not exist$(NC)"; \
		exit 1; \
	fi
	@echo -e "$(GREEN)Pulling monorepo repo$(NC)"
	@$(git_pull_repo)
endif
else
ifeq ($*,All)
	@echo -e "$(GREEN)Pulling all modules$(NC)"
	@for mod in $(MODULES); do \
		if [ -d "$(MODULE_PREFIX)/$$mod" ]; then \
			echo -e "$(GREEN)Pulling module: $$mod$(NC)"; \
			cd $(MODULE_PREFIX)/$$mod && $(MAKE) pull && cd - >/dev/null || exit 1; \
		else \
			echo -e "$(YELLOW)Warning: Module $$mod does not exist, skipping$(NC)"; \
		fi; \
	done
else
	$(call check_module_exists,$*)
	@echo -e "$(GREEN)Pulling module: $*$(NC)"
	@cd $(MODULE_PREFIX)/$* && $(git_pull_repo) || exit 1
endif
endif

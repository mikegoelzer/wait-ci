SHELL := /bin/bash
BUMP_SCRIPT := scripts/bump_version.py
TAG_PREFIX := wait-ci-v
VENVDIR := .venv
UV := uv
PKG_WAIT_CI_PATH := $(shell realpath .)
PKG_WAIT_CI := wait-ci

LOCAL_CURVPYUTILS_PATH := ../curv-python/packages/curvpyutils

# If a local curvpyutils checkout exists at LOCAL_CURVPYUTILS_PATH, install it in
# editable mode so local changes are picked up. Otherwise, fall back to
# installing curvpyutils from PyPI.
ifneq ($(wildcard $(LOCAL_CURVPYUTILS_PATH)),)
DEV_INSTALL_CMD := $(UV) pip install -e .[dev] -e $(LOCAL_CURVPYUTILS_PATH)
CURVPYUTILS_INSTALL_CMD := $(UV) pip install -e $(LOCAL_CURVPYUTILS_PATH)
TOOL_INSTALL_CMD := $(UV) tool install --editable .[dev] --with-editable $(LOCAL_CURVPYUTILS_PATH)
else
DEV_INSTALL_CMD := $(UV) pip install -e .[dev] && $(UV) run pip install curvpyutils
CURVPYUTILS_INSTALL_CMD := $(UV) run pip install curvpyutils
TOOL_INSTALL_CMD := $(UV) tool install --editable .[dev] --with curvpyutils
endif

.PHONY: test clean venv upgrade-venv-for-dev publish-patch publish-minor publish-major release-latest install-dev install-min install-tools-dev bump-patch bump-minor bump-major

venv: $(VENVDIR)/bin/python
$(VENVDIR)/bin/python:
	#$(UV) venv --seed $(VENVDIR)
	$(UV) sync --extra dev

upgrade-venv-for-dev: venv
	$(DEV_INSTALL_CMD)

install-tools-dev:
	$(TOOL_INSTALL_CMD) && \
		echo "✓ Installed $(PKG_WAIT_CI)[dev] as tool..." \
		|| echo "✗ Failed to install $(PKG_WAIT_CI)[dev]..."
	@# Edit shell's rc file to keep the PATH update persistent
	@$(UV) tool update-shell -q && \
		echo "✓ Updated shell to use the new $(notdir $(PKG_WAIT_CI))[dev]..." \
		|| echo "✗ Failed to update shell..."
	$(CURVPYUTILS_INSTALL_CMD)

# alias for install-min
install: install-min

install-dev: install-tools-dev
	@uv sync --dev
	@$(DEV_INSTALL_CMD)
	@echo "✓ wait-ci, global CLI tools + local curvpyutils installed in $(VENVDIR)"

# installs only the package (in editable mode)
install-min: 
	@uv sync --dev
	@echo "🔄 Installing editable install of wait-ci..."
	@if $(UV) pip show -q $(PKG_WAIT_CI) >/dev/null 2>&1; then \
		echo "✓ $(PKG_WAIT_CI) already installed"; \
	else \
		$(UV) pip install -e $(PKG_WAIT_CI); \
		echo "✓ Installed $(PKG_WAIT_CI)..."; \
	fi;

test:
	@# --no-sync is important if curvpyutils is installed as editable local package;
	@# without it, any `uv run` blows away the local package install settings in the venv, requiring
	@# a new `make install-dev`
	$(UV) run --no-sync pytest

clean:
	@$(UV) tool uninstall $(PKG_WAIT_CI) || true; \
		echo "✓ Uninstalled $(PKG_WAIT_CI)...";
	@rm -rf build dist .pytest_cache .ruff_cache .mypy_cache .coverage htmlcov
	@find . -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
	@find . -type d -name .pytest_cache -exec rm -rf {} + 2>/dev/null || true
	@find . -type d -name .mypy_cache -exec rm -rf {} + 2>/dev/null || true
	@find . -type d -name .ruff_cache -exec rm -rf {} + 2>/dev/null || true
	@find . -type f -name "*.log" -exec rm -f {} + 2>/dev/null || true
	@[ -d "$(VENVDIR)" ] && { \
		$(RM) -rf $(VENVDIR) ; \
		echo "✓ Removed $(VENVDIR)"; \
	} || { \
		echo "~ Skipping venv cleanup since $(VENVDIR) does not exist"; \
	}

bump-patch:
	$(UV) run python $(BUMP_SCRIPT) patch

bump-minor:
	$(UV) run python $(BUMP_SCRIPT) minor

bump-major:
	$(UV) run python $(BUMP_SCRIPT) major

publish-patch: test
	$(UV) run python $(BUMP_SCRIPT) patch --push
	$(MAKE) release-latest

publish-minor: test
	$(UV) run python $(BUMP_SCRIPT) minor --push
	$(MAKE) release-latest

publish-major: test
	$(UV) run python $(BUMP_SCRIPT) major --push
	$(MAKE) release-latest

release-latest:
	@version="$$($(UV) run python $(BUMP_SCRIPT) --show-latest)" ; \
	tag="$(TAG_PREFIX)$$version" ; \
	gh release create "$$tag" --title "wait-ci-v$$version" --notes "Automated release $$tag"


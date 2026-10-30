PREFIX ?= $(HOME)/.local
BINDIR ?= $(PREFIX)/bin
DATADIR ?= $(PREFIX)/share

BASH_COMP_DIR ?= $(DATADIR)/bash-completion/completions
ZSH_COMP_DIR  ?= $(DATADIR)/zsh/site-functions
FISH_COMP_DIR ?= $(DATADIR)/fish/vendor_completions.d

.PHONY: all install link uninstall test

all:
	@echo "denv build & installation targets:"
	@echo "  make install    - Install denv and shell completions to $(PREFIX)"
	@echo "  make link       - Symlink denv and shell completions (developer mode)"
	@echo "  make uninstall  - Remove denv and completions from $(PREFIX)"
	@echo "  make test       - Run syntax verification and integration test suite"

install:
	install -d $(DESTDIR)$(BINDIR)
	install -m 0755 bin/denv $(DESTDIR)$(BINDIR)/denv
	@# Shell completions
	install -d $(DESTDIR)$(BASH_COMP_DIR) $(DESTDIR)$(ZSH_COMP_DIR) $(DESTDIR)$(FISH_COMP_DIR)
	install -m 0644 completions/bash/denv $(DESTDIR)$(BASH_COMP_DIR)/denv
	install -m 0644 completions/zsh/_denv $(DESTDIR)$(ZSH_COMP_DIR)/_denv
	install -m 0644 completions/fish/denv.fish $(DESTDIR)$(FISH_COMP_DIR)/denv.fish
	@echo "Successfully installed denv to $(DESTDIR)$(BINDIR)/denv"

link:
	install -d $(DESTDIR)$(BINDIR)
	ln -sf $(CURDIR)/bin/denv $(DESTDIR)$(BINDIR)/denv
	@# Shell completions
	install -d $(DESTDIR)$(BASH_COMP_DIR) $(DESTDIR)$(ZSH_COMP_DIR) $(DESTDIR)$(FISH_COMP_DIR)
	ln -sf $(CURDIR)/completions/bash/denv $(DESTDIR)$(BASH_COMP_DIR)/denv
	ln -sf $(CURDIR)/completions/zsh/_denv $(DESTDIR)$(ZSH_COMP_DIR)/_denv
	ln -sf $(CURDIR)/completions/fish/denv.fish $(DESTDIR)$(FISH_COMP_DIR)/denv.fish
	@echo "Successfully symlinked denv and completions -> $(DESTDIR)$(BINDIR)/denv"

uninstall:
	rm -f $(DESTDIR)$(BINDIR)/denv
	rm -f $(DESTDIR)$(BASH_COMP_DIR)/denv
	rm -f $(DESTDIR)$(ZSH_COMP_DIR)/_denv
	rm -f $(DESTDIR)$(FISH_COMP_DIR)/denv.fish
	@echo "Successfully uninstalled denv and completions from $(DESTDIR)$(PREFIX)"

test:
	@echo "Checking Bash syntax..."
	@bash -n bin/denv
	@bash -n install.sh
	@bash -n tests/test_denv.sh
	@bash -n completions/bash/denv
	@if command -v shellcheck >/dev/null 2>&1; then \
		echo "Running shellcheck..."; \
		shellcheck bin/denv install.sh tests/test_denv.sh completions/bash/denv; \
	fi
	@echo "Running integration test suite..."
	@tests/test_denv.sh

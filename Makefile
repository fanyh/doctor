PREFIX ?= $(HOME)/.local

install:
	mkdir -p $(PREFIX)/bin
	ln -sf $(CURDIR)/bin/doctor $(PREFIX)/bin/doctor

uninstall:
	rm -f $(PREFIX)/bin/doctor

.PHONY: install uninstall

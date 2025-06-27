# Makefile for Sybase Prometheus Exporter

# Configuration
PREFIX ?= /usr/local
BINDIR ?= $(PREFIX)/bin
SYSCONFDIR ?= /etc
SYSTEMDDIR ?= /usr/lib/systemd/system

# Files
SCRIPT = sybase_exporter.sh
CONFIG = sybase_exporter.conf
SERVICE = sybase_exporter.service

# Targets
.PHONY: all install uninstall clean rpm

all:
	@echo "Available targets:"
	@echo "  install   - Install the exporter"
	@echo "  uninstall - Uninstall the exporter"
	@echo "  clean     - Clean up temporary files"
	@echo "  rpm       - Build RPM package (requires rpmbuild)"

install:
	@echo "Installing Sybase Prometheus Exporter..."
	install -d $(DESTDIR)$(BINDIR)
	install -m 755 $(SCRIPT) $(DESTDIR)$(BINDIR)/sybase_exporter
	install -d $(DESTDIR)$(SYSCONFDIR)
	install -m 644 $(CONFIG) $(DESTDIR)$(SYSCONFDIR)/sybase_exporter.conf
	install -d $(DESTDIR)$(SYSTEMDDIR)
	install -m 644 $(SERVICE) $(DESTDIR)$(SYSTEMDDIR)/sybase_exporter.service
	@echo "Installation complete."
	@echo "To start the service, run: systemctl start sybase_exporter"

uninstall:
	@echo "Uninstalling Sybase Prometheus Exporter..."
	rm -f $(DESTDIR)$(BINDIR)/sybase_exporter
	rm -f $(DESTDIR)$(SYSCONFDIR)/sybase_exporter.conf
	rm -f $(DESTDIR)$(SYSTEMDDIR)/sybase_exporter.service
	@echo "Uninstallation complete."

clean:
	rm -f *.tar.gz *.rpm

rpm:
	./build_rpm.sh

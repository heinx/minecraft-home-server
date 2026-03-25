# Lima-based test runner for Apple Silicon Macs.
# Uses Apple Virtualization.framework + Rosetta 2 for fast x86_64 binary support.
#
# Prerequisites: brew install lima
#
# Usage:
#   make up       # Create and provision VM (~30s)
#   make test     # Run test suite
#   make ssh      # SSH into VM
#   make halt     # Stop VM (preserves state)
#   make destroy  # Remove VM entirely
#   make retest   # Re-run tests without rebuilding VM

LIMA_INSTANCE := minecraft-test
LIMA_CONFIG   := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))lima.yaml
REPO_ROOT     := $(abspath $(dir $(abspath $(lastword $(MAKEFILE_LIST))))/..)

.PHONY: up ssh test retest halt destroy status clean

up:
	@if limactl list --json 2>/dev/null | grep -q '"name":"$(LIMA_INSTANCE)"'; then \
		echo "Instance '$(LIMA_INSTANCE)' exists, starting..."; \
		limactl start $(LIMA_INSTANCE) 2>/dev/null || true; \
	else \
		limactl create --name=$(LIMA_INSTANCE) \
			--set '.mounts = [{"location": "$(REPO_ROOT)", "mountPoint": "/vagrant", "writable": true}]' \
			$(LIMA_CONFIG); \
		limactl start $(LIMA_INSTANCE); \
	fi
	limactl shell $(LIMA_INSTANCE) -- sudo bash /vagrant/tests/provision_lima.sh

ssh:
	limactl shell $(LIMA_INSTANCE)

test: up
	limactl shell $(LIMA_INSTANCE) -- sudo /vagrant/tests/run_tests.sh

retest:
	limactl shell $(LIMA_INSTANCE) -- sudo /vagrant/tests/run_tests.sh

halt:
	limactl stop $(LIMA_INSTANCE)

destroy:
	limactl delete --force $(LIMA_INSTANCE) 2>/dev/null || true

status:
	limactl list $(LIMA_INSTANCE)

clean: destroy

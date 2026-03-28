ROOT := $(shell cd ../.. && pwd)
SEEDINK := $(ROOT)/seedink3.scm
HERE := $(shell pwd)

.PHONY: check check-unit benchmark

check: check-unit
	cd $(ROOT) && bash $(HERE)/checks/run-checks.sh

check-unit:
	cd $(ROOT) && scheme --script $(HERE)/checks/checks.scm

benchmark:
	@echo "── n-queen ──"
	cd $(ROOT) && scheme --script $(SEEDINK) $(HERE)/benchmarks/n-queen.seed
	@echo ""
	@echo "── collatz ──"
	cd $(ROOT) && scheme --script $(SEEDINK) $(HERE)/benchmarks/collatz.seed

ROOT := $(shell cd ../.. && pwd)
SEEDINK := $(ROOT)/seedink3.scm
HERE := $(shell pwd)

.PHONY: check benchmark

check:
	cd $(ROOT) && bash $(HERE)/checks/run-checks.sh

benchmark:
	@echo "── n-queen ──"
	cd $(ROOT) && scheme --script $(SEEDINK) $(HERE)/benchmarks/n-queen.seed
	@echo ""
	@echo "── collatz ──"
	cd $(ROOT) && scheme --script $(SEEDINK) $(HERE)/benchmarks/collatz.seed

ROOT := $(shell cd ../.. && pwd)
SEEDINK := $(ROOT)/seedink3.scm
HERE := $(shell pwd)

.PHONY: help check check-unit benchmark

help:
	@echo "Seed3 Makefile targets:"
	@echo ""
	@echo "  check       Run 152 unit tests then 7 end-to-end tests"
	@echo "  check-unit  Run 152 unit tests (parse, annotate, classify, bta, codegen)"
	@echo "  benchmark   Run n-queen, collatz, abacus, and gremlin-pipeline benchmarks"
	@echo "  help        Show this message"

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
	@echo ""
	@echo "── abacus ──"
	cd $(ROOT) && scheme --script $(SEEDINK) $(HERE)/benchmarks/abacus.seed3
	@echo ""
	@echo "── gremlin-pipeline ──"
	cd $(ROOT) && scheme --script $(SEEDINK) $(HERE)/benchmarks/gremlin-pipeline.seed3

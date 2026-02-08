SCHEME = scheme

.PHONY: help repl check benchmarks

help:
	@echo "make repl   — start the Seed REPL"
	@echo "make check  — run all 192 tests"
	@echo "make benchmarks — run benchmarks (N-Queens, Collatz, Abacus)"

repl:
	$(SCHEME) --script seedink.scm

check:
	$(SCHEME) --script checks.scm

benchmarks:
	bash make-benchmark.sh

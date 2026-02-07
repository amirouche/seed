SCHEME = scheme

.PHONY: help repl check benchmark

help:
	@echo "make repl   — start the Seed REPL"
	@echo "make check  — run all 192 tests"
	@echo "make benchmark — run benchmarks (N-Queens, Collatz, Abacus)"

repl:
	$(SCHEME) --script seed.scm

check:
	$(SCHEME) --script seed2-checks.scm

benchmark:
	bash make-benchmark.sh

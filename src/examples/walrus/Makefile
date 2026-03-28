ROOT = ../..
SEEDINK2 = $(ROOT)/seedink2.scm

.PHONY: all seed2 chez clean

all: seed2 chez

seed2:
	@echo "=== Seed2 (vau + walrus :=) ==="
	cd $(ROOT) && scheme --script seedink2.scm examples/walrus/walrus.seed2

chez:
	@echo "=== Chez Scheme (syntax-rules) ==="
	scheme --script walrus.scm

dump:
	@echo "=== Compiled Chez output from Seed2 ==="
	cd $(ROOT) && scheme --script seedink2.scm --dump examples/walrus/walrus.seed2

clean:
	@echo "Nothing to clean"

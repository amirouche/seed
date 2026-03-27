ROOT = ../..
SEEDINK2 = $(ROOT)/seedink2.scm

.PHONY: all seed2 chez clean

all: seed2 chez

seed2:
	@echo "=== Seed2 (vau + define env) ==="
	cd $(ROOT) && scheme --script seedink2.scm examples/aif/aif.seed2

chez:
	@echo "=== Chez Scheme (syntax-rules) ==="
	scheme --script aif.scm

dump:
	@echo "=== Compiled Chez output from Seed2 ==="
	cd $(ROOT) && scheme --script seedink2.scm --dump examples/aif/aif.seed2

clean:
	@echo "Nothing to clean"

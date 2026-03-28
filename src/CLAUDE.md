# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This repository contains **Seed**, a nanopass compiler for a vau-based Scheme dialect. Seed compiles a simplified Scheme with `vau` (fexprs/operatives) as the sole abstraction primitive, where `lambda` desugars to `(wrap (vau params #f body))`.

The compiler is implemented in Chez Scheme and uses a **5-pass nanopass architecture**:
1. **parse**: Source S-expressions → L1 AST
2. **annotate**: L1 AST → L2 AST (marks variables as local/free)
3. **classify**: L2 AST → L3 AST (separates `lambda` from `vau`)
4. **bta**: L3 AST → L4 AST (binding-time analysis for optimization)
5. **codegen**: L4 AST → Chez Scheme code

## Commands

### Building and Testing
```bash
# Run all 195 tests (checks.scm loads and tests seed.scm)
make check
# or directly:
scheme --script checks.scm

# Run benchmarks (N-Queens, Collatz, Abacus)
make benchmarks
# or directly:
bash make-benchmark.sh

# Start Seed REPL
make repl
# or directly:
scheme --script seed.scm
```

### Benchmark Configuration
The benchmark script supports extensive customization:
```bash
# Run specific benchmark
bash make-benchmark.sh --only=nqueens
bash make-benchmark.sh --only=collatz
bash make-benchmark.sh --only=abacus

# Adjust parameters
bash make-benchmark.sh --nq-n=16              # N-Queens board size (default: 14)
bash make-benchmark.sh --collatz=30000000     # Collatz limit (default: 20M)
bash make-benchmark.sh --abacus-expr-depth=30 # Abacus tree depth (default: 27)
bash make-benchmark.sh --iters=3              # Repetitions (default: 1)

# Enable dev mode (optimize-level 0, GC enabled, profiling)
bash make-benchmark.sh --dev

# Combine options
bash make-benchmark.sh --only=abacus --dev --iters=5
```

### Running Seed Programs
```bash
# Run a .seed or .k file (automatically provides ground-env for vau/eval)
scheme --script seed.scm path/to/program.seed
```

## Architecture

### Core Files
- **seed.scm** (1765 lines): Main compiler implementation with all 5 passes
- **checks.scm** (991 lines): Comprehensive test suite with 195 tests
- **match.scm** (914 lines): SRFI-241 pattern matcher (local copy, used by seed.scm)

### Key Design Decisions

**Vau as Sole Primitive**
`vau` is the only abstraction mechanism. It receives both the dynamic environment and unevaluated arguments:
- `(vau (a b c) env body)` — operative with env parameter
- `(vau (a b c) #f body)` — operative ignoring environment (canonical ignored form)
- `(lambda (a b c) body)` — desugars to `(wrap (vau (a b c) #f body))`

The `#f` sentinel for environment parameters is canonical; `_` and `%ignore` are normalized to `#f` during parsing.

**Nanopass Compilation Strategy**
Each pass performs a single, well-defined transformation:
- **annotate** (Pass 2) tracks variable scope without changing structure
- **classify** (Pass 3) introduces the `(lam params body)` node to separate applicatives from operatives
- **bta** (Pass 4) performs binding-time analysis, annotating `vau` nodes with optimization metadata
- **codegen** (Pass 5) generates Chez Scheme code, compiling `vau` to a 2-arg procedure `(lambda (env params) body)`

**Pattern Matching**
The compiler uses SRFI-241 `match` extensively. Catamorphic patterns like `,[var]` auto-recurse, used in passes where the environment doesn't change (annotate's if/begin/call cases). Binding forms (let/letrec/vau) use explicit recursion because they extend the environment.

### Benchmark Structure

Benchmarks live in `benchmarks/*/`:
- Each benchmark has a `.seed` file (Seed source) and `.scm` file (R6RS Chez Scheme library)
- `base.body.scm` contains the `dev!` configuration function used by benchmark drivers
- The `make-benchmark.sh` script orchestrates benchmarks and parses timing output

**Benchmark Timing:**

All benchmarks use Chez Scheme's `(time ...)` form for execution timing:

**Simple benchmarks** (n-queens, collatz):
- Single `time` wrapper around entire computation
- Reports total execution time to stderr

**Abacus benchmarks** (abacus, abacus2):
- Two separate `time` wrappers: one for tree-building, one for evaluation
- Allows understanding performance breakdown of the two phases

**Chez `time` output format:**
```
(time ...)
    no collections
    0.123456s elapsed cpu time
    0.123456s elapsed real time
    1024 bytes allocated
```

The `make-benchmark.sh` script extracts "elapsed real time" values using sed patterns. For abacus benchmarks, it extracts both time values (in order) and computes their sum as total time.

**Seedink timing:**
Uses `time` form in `run-file` to measure entire pipeline (Seed compile + Chez JIT execution) as one operation.

### Development Mode

The `dev!` function (in seed.scm and benchmarks/base.scm) toggles optimization/profiling:
- `(dev! #f)` — production mode: optimize-level 3, GC disabled, no profiling
- `(dev! #t)` — dev mode: optimize-level 0, GC enabled, profiling and debugging enabled

Default is `#f` (production). Override with `--dev` flag in benchmarks.

## Workflow Notes

**Testing**
- All tests are in `checks.scm`, which loads `seed.scm` and runs 195 tests
- Tests cover parsing, annotation, classification, BTA, and roundtrips
- `make check` is the standard way to verify correctness

**Benchmarking**
- Benchmarks compare Seed (vau) vs native Chez Scheme performance
- Results show compile time, execute time, and wall time separately
- Use `--dev` flag to enable profiling when investigating performance issues

**AST Transformations**
Each pass has a corresponding `lN->src` function for debugging:
- `ast->src` (L1), `l2->src` (L2), `l3->src` (L3), `l4->src` (L4)
- These functions convert ASTs back to readable S-expressions
- Useful for inspecting intermediate representations during development

**Ground Environment**
`ground-env` (defined in seed.scm) provides the runtime environment for `eval` and `vau` programs. It includes standard Scheme procedures and is automatically provided when running `.seed` files via `run-file`.

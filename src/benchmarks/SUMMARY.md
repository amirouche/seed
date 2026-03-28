# Benchmark Summary

Chez Scheme optimize-level 2, GC disabled (production mode).
Machine: 121GB RAM, Linux 6.17.

## Results

| Benchmark | Seedink2 (Seed2) | Chez Scheme | Ratio (Seed2 / Chez) |
|-----------|---------------:|-----------:|:--------------------:|
| N-Queens (N=14)             |  26.97s |  27.03s | ~tied              |
| Collatz (limit=20M)         |  12.52s |  13.29s | 1.06x faster       |
| Abacus (depth=27)           |  12.03s |  11.86s | 1.01x slower       |
| Abacus2 (depth=27)          |  15.96s |  22.86s | 1.43x faster       |
| Gremlin-fold (N=20000)      |  24.17s |  23.87s | 1.01x slower       |
| Gremlin-pipeline (N=20000)  |  24.26s |  23.70s | 1.02x slower       |
| **TOTAL**               |**115.91s**|**122.61s**| **1.06x faster** |

### Gremlin Pipeline (N=20000 vertices, E=20 edges/vertex)

| Variant | DSL style | Mechanism | Time |
|---|---|---|---:|
| Chez pipeline   | flat `(traverse g (V) (as a) (out) ...)` | `syntax-case` macro | 23.70s |
| Chez gremlin-fold | nested `(gremlin-fold a stream acc body)` | `syntax-rules` macro | 23.87s |
| Seed2 pipeline | flat `(traverse g (V) (as a) (out) ...)` | recursive vau + specializer | 24.26s |
| Seed2 gremlin-fold | nested `(gremlin-fold a stream acc body)` | vau + specializer | 24.17s |

All compile-time variants within ~2%.

## Observations

### Gremlin Pipeline: vau as a macro system

The Gremlin pipeline benchmark demonstrates vau operatives as an alternative
to macros for building compile-time DSLs.  Both versions use the same flat
TinkerPop-inspired syntax:

```scheme
(traverse g
  (V)                          ;; g.V()
  (as a)                       ;; .as('a')
  (out)                        ;; .out()
  (as b)                       ;; .as('b')
  (where (same-group? g a b))  ;; .filter{sameGroup('a','b')}
  (out)                        ;; .out()
  (as c)                       ;; .as('c')
  (where (same-group? g a c))  ;; .filter{sameGroup('a','c')}
  (where (edge? g c a))        ;; .filter{hasEdge('c','a')}
  (count))                     ;; .count()
```

Both compile to the same nested-loop code at compile time.  The difference
is in the definition of `traverse`:

**Seed2 (vau):** `process-pipeline` is a recursive vau that receives the
step list as a rest-arg (static `(quot ...)` data).  The specializer
constant-folds `car`/`cdr`/`null?`/`eq?`/`cons` on the step list, and
a new rule compiles `(eval (quot (process-pipeline ...)) (dyn-env))` inline
by re-specializing the vau body.  The entire 10-step pipeline unfolds at
compile time.

**Chez (syntax-case):** `traverse-steps` is a recursive `syntax-case` macro
that pattern-matches the first step and recurses on the rest.  `datum->syntax`
breaks hygiene to thread the accumulator variable.

The key difference is *what you need to know to write it*:
- The Seed2 vau is written as ordinary code — `car`, `cdr`, `if`, `eval`
- The Chez macro requires `syntax-case`, `datum->syntax`, literal-set
  keywords, and template splicing

Both produce identical nested loops.  The vau is runtime code that the
compiler happens to fully evaluate at compile time; the macro is explicitly
compile-time code.

### Gremlin Fold: vau operative vs syntax-rules macro

The gremlin-fold benchmark uses a 5-line vau operative (Seed2) or a 4-line
`syntax-rules` macro (Chez).  Both produce identical `fold-left`-style
nested loops.  The Seed2 version shares the caller's scope (no hygiene
barrier for `acc`), while the Chez version requires the user to name the
accumulator explicitly.

### Why Seed beats Chez on Abacus2

See [LIMITS.md](LIMITS.md) for details. In short: the Seed benchmarks
carry a hand-optimized runtime pattern matcher (`pmatch`) with fast paths
for single-variable catamorphism. SRFI-241 `match` generates correct but
generic code. The speed advantage (~43%) comes from specialization, not
from a fundamental compiler advantage.

### Why Chez wins on Abacus

Abacus uses a simpler pattern structure where SRFI-241's generic code
doesn't have the same overhead as in Abacus2. The ~1% Chez advantage
is within noise.

### N-Queens: effectively tied

N-Queens is pure lambda/letrec computation with no operatives. The Seed
compiler adds a thin wrapper (ground-env setup, `run-file` overhead) but
the compiled inner loops are identical. The difference is in the noise.

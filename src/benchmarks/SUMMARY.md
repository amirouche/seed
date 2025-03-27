# Benchmark Summary

Chez Scheme optimize-level 2, GC disabled (production mode).
Machine: 121GB RAM, Linux 6.17.

## Results

| Benchmark | Seedink (Seed1) | Seedink2 (Seed2) | Chez Scheme | Ratio (Seed best / Chez) |
|-----------|----------------:|-----------------:|------------:|:------------------------:|
| N-Queens  |         27.89s  |          27.64s  |     27.01s  | 1.02x slower             |
| Collatz   |         12.49s  |          12.52s  |     13.25s  | 1.06x faster             |
| Abacus    |         11.53s  |          12.05s  |     11.48s  | ~tied                    |
| Abacus2   |         15.91s  |          16.11s  |     22.46s  | 1.41x faster             |
| Gremlin   |         12.36s  |          12.33s  |     12.17s  | ~tied                    |
| **TOTAL** |     **80.18s**  |      **80.65s**  | **86.37s**  | **1.08x faster**         |

### Gremlin Pipeline (N=20000 vertices, E=20 edges/vertex)

| Variant | DSL style | Mechanism | Time |
|---|---|---|---:|
| Chez pipeline   | flat `(traverse g (V) (as a) (out) ...)` | `syntax-case` macro | 23.67s |
| Chez gremlin-fold | nested `(gremlin-fold a stream acc body)` | `syntax-rules` macro | 23.84s |
| Seed2 gremlin-fold | nested `(gremlin-fold a stream acc body)` | vau + specializer | 23.93s |
| Seed2 pipeline | flat `(traverse g (V) (as a) (out) ...)` | recursive vau + specializer | 24.01s |

All four within ~1.5%.  The Seed2 pipeline DSL compiles a flat TinkerPop-style
step list into direct nested loops at compile time, matching Chez's syntax-case
macro performance.

## Observations

### Seed2 adds no overhead

Seed1 and Seed2 produce nearly identical execution times on all benchmarks.
The `(values news out)` calling convention machinery is zero-cost when not
used, and adds negligible overhead (~0.2%) when used (Gremlin).

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

### Gremlin Fold: `as!` operative vs `let` bindings

The original Gremlin benchmark uses `gremlin-fold`, a 5-line vau operative
(Seed2) or a 4-line `syntax-rules` macro (Chez).  Both produce identical
`fold-left`-style code.  The Seed2 version shares the caller's scope
(no hygiene barrier for `acc`), while the Chez version requires the user
to name the accumulator explicitly.

### Why Seed beats Chez on Abacus2

See [LIMITS.md](LIMITS.md) for details. In short: the Seed benchmarks
carry a hand-optimized runtime pattern matcher (`pmatch`) with fast paths
for single-variable catamorphism. SRFI-241 `match` generates correct but
generic code. The speed advantage (~41%) comes from specialization, not
from a fundamental compiler advantage.

### Why Chez wins on N-Queens

N-Queens is pure lambda/letrec computation with no operatives. The Seed
compilers add a thin wrapper (ground-env setup, `run-file` overhead) that
accounts for the ~2-3% difference. The compiled inner loops are identical.

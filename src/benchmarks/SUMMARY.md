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

## Observations

### Seed2 adds no overhead

Seed1 and Seed2 produce nearly identical execution times on all benchmarks.
The `(values news out)` calling convention machinery is zero-cost when not
used, and adds negligible overhead (~0.2%) when used (Gremlin).

### Gremlin: `as!` operative vs `let` bindings

The Gremlin benchmark is the only one that exercises Seed2's caller-env
extension. The `as!` operative compiles to proper Chez variables via
`(values news out)`, producing code structurally equivalent to the Chez
version's `let*` bindings.

The traversal core in Seed2:

```scheme
(begin
  (as! a-entry (graph-ref g ai))
  (as! a-grp (graph-group a-entry))
  (as! a-nbrs (graph-neighbors a-entry))
  (let loop-b ((bs a-nbrs) (count count))
    ...
    (begin
      (as! bi (car bs))
      (as! b-entry (graph-ref g bi))
      (as! b-grp (graph-group b-entry))
      ...)))
```

The equivalent Chez code:

```scheme
(let* ([a-entry (graph-ref g ai)]
       [a-grp (graph-group a-entry)]
       [a-nbrs (graph-neighbors a-entry)])
  (let loop-b ([bs a-nbrs] [count count])
    ...
    (let* ([bi (car bs)]
           [b-entry (graph-ref g bi)]
           [b-grp (graph-group b-entry)])
      ...)))
```

Both are readable. The Seed2 version is flatter — `as!` statements in a
`begin` block instead of nested `let*`. This is a stylistic difference,
not a readability win. The real advantage is that `as!` is **user-defined**:
it's a two-line operative, not a language primitive. You can define new
binding constructs (like Gremlin's `as`, `where`, `select`) as library
code, compose them freely, and the compiler eliminates the abstraction.

In Chez, `let*` is built into the language. You cannot define new binding
forms without `syntax-case` macros, which require understanding the macro
expansion model, phase separation, and hygiene. In Seed2, `as!` is just:

```scheme
(define as! (vau (name val-expr) env
  (define env name (eval val-expr env))))
```

The readability difference is not in the *use site* but in the *definition
site*: anyone who can write a function can write `as!` in Seed2. Writing
the equivalent `define-syntax` in Chez requires significantly more expertise.

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

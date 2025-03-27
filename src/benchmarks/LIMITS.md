# Benchmark Limitations

## Abacus/Abacus2: Seed pmatch vs SRFI-241 match

The abacus benchmarks compare Seed's runtime `pmatch` against Chez's
SRFI-241 `match` macro. Seed is faster (~30% on abacus2), but the two
implementations are not equivalent. The Seed pmatch is a minimal runtime
matcher; SRFI-241 is a full compile-time macro system.

### What Seed's pmatch supports

- Pair/list destructuring
- Unquote variables `,x`
- Ellipsis repetition `,...`
- Guard clauses `(guard pred)`
- Implicit catamorphism (recursive `loop` function)

### What Seed's pmatch is missing vs SRFI-241

**Structural:**
- Vector patterns `#(x ...)`
- Named catamorphism transformers `,[f -> y]`
- Nested ellipsis (ellipsis inside ellipsis)
- Dotted-pair / improper list patterns
- Literal/constant patterns with `equal?`

**Safety:**
- Duplicate pattern variable detection
- Cyclic list detection (SRFI-241 uses tortoise-and-hare)
- Catamorphism binding validation
- Structured error reporting (`syntax-violation`)

### Why Seed is faster

The speed advantage comes from hand-optimized fast paths for the specific
patterns the abacus evaluator uses (single-variable catamorphism with
ellipsis):

- `simple-cata-pattern?` detects the common `,[x]` case
- `match-each-ultra-fast` bypasses all pattern matching overhead for this
  case — it's a direct map of the loop function
- `match-each-fast` handles single-variable ellipsis without multi-variable
  accumulator overhead

SRFI-241's `gen-map-values` generates correct but generic code that handles
all patterns uniformly, including reverse + let-values unpacking at each step.

The comparison is fair in the sense that both solve the same problem, but the
Seed version is specialized while the Chez version is general-purpose.

## Gremlin Pipeline: vau operative vs syntax-case macro

The pipeline benchmark compiles a flat TinkerPop-style step list into nested
loops.  Both Seed2 and Chez produce structurally identical code and run within
~1.5% of each other.  The comparison is fair — same algorithm, same loop
structure, same graph.

### Where predicate evaluation

The Seed2 pipeline has one residual runtime cost: `where` predicates
(e.g., `(same-group? g a b)`) are still evaluated via `seed-eval` at runtime
because the traversal variables `a`, `b`, `c` are bound dynamically by
`(define env name (car items))` at each loop iteration.  They are in the
runtime env alist, not as Chez locals.

The Chez `syntax-case` version doesn't have this issue — `where` predicates
are inlined directly at compile time because `syntax-case` has full access
to the variable bindings through hygienic expansion.

In practice this difference is negligible (~0.3s out of ~24s) because the
predicates are simple function calls and `env-ref` lookup is fast (the
binding is always at the head of the alist due to the `define env` ordering).

### Definition complexity

The Seed2 `process-pipeline` is 33 lines of ordinary Scheme code using
`car`, `cdr`, `if`, `eval`.  The Chez `traverse-steps` is 30 lines of
`syntax-case` macro code requiring `datum->syntax` for hygiene-breaking,
literal keyword sets, and template splicing.  Both are manageable, but the
vau version requires no macro expertise.

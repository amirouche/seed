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

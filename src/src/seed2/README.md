# Seed2 — Compilation Strategy for Caller-Env Extension

## Overview

Seed2 extends the Seed nanopass style compiler with support for vau
operatives that **extend the caller's environment** — defining new
bindings visible at the call site.

The compilation strategy uses a `(values news out)` calling convention:
the operative returns two lists via `values`, and the call site unpacks
them with nested `call-with-values`.

## The `(values news out)` Convention

Every compiled vau call that extends the caller's environment returns
exactly **two values**:

- **`news`** — a list of values for environment additions (the names
  are known statically from `(define env name expr)` nodes in the vau body)
- **`out`** — a list of return values from the operative

The call site uses nested `call-with-values` to unpack both:

```scheme
(call-with-values
  (lambda ()
    ;; compiled operative body
    (values (list <env-addition-values...>)    ;; news
            (list <return-values...>)))        ;; out
  (lambda (news out)
    (call-with-values
      (lambda () (apply values news))
      (lambda (<env-addition-names...>)        ;; unpacked as Chez variables
        (call-with-values
          (lambda () (apply values out))
          (lambda (<return-names...>)          ;; unpacked return value(s)
            <continuation...>))))))
```

This keeps the caller environment **immutable** — no alist mutation, no
`set-car!/set-cdr!`, no runtime `env-ref` lookups. The new bindings
become proper Chez Scheme lambda parameters.

## Four Forms of `define`

Seed2 unifies all definition forms under `define`:

| Form | Meaning |
|------|---------|
| `(define name expr)` | Local binding (handled by `transform-to-letrec`) |
| `(define (names...) expr)` | Local destructuring bind from a list |
| `(define env name expr)` | Inject single binding into target environment |
| `(define env (names...) expr)` | Destructuring into target environment |

Forms 3 and 4 are what trigger the `(values news out)` transformation.
The `env` parameter refers to the vau's captured caller environment.

## Worked Example: `multi-define`

### Source

```scheme
(define setup (vau () env
  (define env x 42)
  (define env y 99)))
(setup)
(display x)
(display " ")
(display y)
(newline)
```

### Compilation

The compiler:

1. **Parses** `(define env x 42)` as a 3-arg define AST node
2. **Specializes** the vau body at the `(setup)` call site, substituting
   parameters. The `env` reference becomes `(dyn-env)`.
3. **Collects** the `define` nodes: names = `(x y)`, values = `(42 99)`,
   stripped body = `(void)`
4. **Generates** `call-with-values` with `(values news out)`:

```scheme
(call-with-values
  (lambda ()
    (values (list 42 99)      ;; news: x=42, y=99
            (list #f)))       ;; out: void (setup returns nothing)
  (lambda (news out)
    (call-with-values
      (lambda () (apply values news))
      (lambda (x y)           ;; env additions become lambda params
        (call-with-values
          (lambda () (apply values out))
          (lambda (_ret)      ;; return value (unused)
            (begin
              (display x)     ;; bare Chez variable, not env-ref
              (display " ")
              (display y)
              (newline))))))))
```

Output: `42 99`

## Worked Example: `frob` (define + return)

### Source

```scheme
(define frob (vau (a a*) env
  (define env a* (+ 40 2 (eval a env)))
  (+ 40 1 (eval a env))))
(display (frob 1 next))
(newline)
(display next)
(newline)
```

The `frob` operative both:
- **Extends** the caller env: defines `next = (+ 40 2 1) = 43`
- **Returns** a value: `(+ 40 1 1) = 42`

### Ideal compiled target

```scheme
(call-with-values
  (lambda ()
    (let ([a 1])
      (values (list (+ 40 2 a))       ;; news: next=43
              (list (+ 40 1 a)))))     ;; out: return=42
  (lambda (news out)
    (call-with-values
      (lambda () (apply values news))
      (lambda (next)                   ;; env addition: next=43
        (call-with-values
          (lambda () (apply values out))
          (lambda (frob-ret)           ;; return value: 42
            (display frob-ret)         ;; prints 42
            (newline)
            (display next)             ;; prints 43
            (newline)))))))
```

Output: `42\n43`

### Current limitation

When the vau call appears as a **sub-expression** (e.g., `(display (frob 1 next))`
rather than as a statement), the `(values news out)` transformation requires
lifting the call out of the expression. Currently, sub-expression vau calls
fall back to the runtime path (env alist mutation + `env-ref` lookup). The
`(values news out)` path is used when the vau call is at statement level
in a `begin` block.

## Compilation Pipeline

```
Source (.seed)
  │
  ├─ transform-to-letrec    ;; group defines into nested letrec blocks
  │
  ├─ parse                   ;; S-expr → L1 AST
  │   └─ (define env name expr) → (define <env-ast> <name-ast> <val-ast>)
  │   └─ (define env (names...) expr) → desugared to let + individual defines
  │   └─ internal defines in begin → transform-to-letrec → letrec
  │
  ├─ annotate                ;; L1 → L2 (mark local/free)
  ├─ classify                ;; L2 → L3 (separate lam from vau)
  ├─ bta                     ;; L3 → L4 (binding-time analysis)
  │
  └─ codegen                 ;; L4 → Scheme
      └─ codegen-begin       ;; handles vau calls with define nodes
          ├─ specialize vau body at call site
          ├─ collect-defines: extract (names, values, stripped-body)
          └─ emit (values news out) + nested call-with-values
```

## Test Suite

Tests live in `src/seed2/checks/`. Each test has three files:

- `.seed` — source program
- `.expected` — expected stdout
- `.scm` — compiled Scheme output (generated by `seedink2c.scm`)

Run all tests:

```bash
bash src/seed2/checks/run-checks.sh
```

## Runtime Fallback

When the compiler cannot statically determine the defined names (e.g.,
dynamic names computed at runtime, or operatives that use `eval` to
construct define expressions), the fallback path uses:

- `seed-eval` — interpreter that evaluates expressions in the env alist
- `set-car!/set-cdr!` — mutates the env alist to add bindings
- `env-ref` — looks up bindings from the env alist at runtime

The `provide-with-eval` example demonstrates this path.

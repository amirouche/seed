# Seed Calling Convention — Implementation Specification

## Overview

Seed is a compiler for a Kernel-inspired language where `vau` (fexprs / operatives)
is the sole abstraction primitive. `lambda` desugars to `(wrap (vau params #f body))`.

The key property: operatives receive unevaluated syntax and the caller's dynamic
environment. Applicatives (`wrap`) pre-evaluate their arguments before passing them.

### Design Priorities

1. **Readability** — the compiler code should be clear and straightforward
2. **Correctness** — handle all vau semantics generically, no specialization for particular vau idioms
3. **Performance** — optimize through general mechanisms (BTA, specialization, dispatch), not pattern-specific shortcuts

### Top-Level Program Structure

A seed3 program is a sequence of top-level `define` forms followed by
expressions. Top-level defines are **not** transformed into `letrec` —
they remain sequential definitions.

```scheme
(define x 42)
(define (add1 y) (+ y 1))
(display (add1 x))
```

---

## Primitive: Immutable Pair

All environments and combiner tags are built from a single immutable pair type.
No `set-car!` or `set-cdr!` on this type — ever.

```scheme
(define-record-type <pair>
  (make-pair head tail)
  pair?
  (head pair-head)
  (tail pair-tail))
```

---

## Tagged Types

### Environment

An environment is a tagged linked list of `(name . value)` cells.

```scheme
(define (env-empty)
  (make-pair 'environment '()))

(define (env? x)
  (and (pair? x) (eq? (pair-head x) 'environment)))

(define (env-extend env name value)
  (assert (env? env))
  (make-pair 'environment (make-pair (make-pair name value) (pair-tail env))))

(define (env-lookup env name)
  (assert (env? env))
  (let loop ((bindings (pair-tail env)))
    (cond
      [(null? bindings) (error 'env-lookup "unbound" name)]
      [(eq? (pair-head (pair-head bindings)) name) (pair-tail (pair-head bindings))]
      [else (loop (pair-tail bindings))])))
```

### Operative

An operative is a tagged procedure receiving `(caller-env . unevaluated-args)`.

```scheme
(define (make-operative proc)
  (make-pair 'operative proc))

(define (operative? x)
  (and (pair? x) (eq? (pair-head x) 'operative)))

(define (operative-proc x)
  (assert (operative? x))
  (pair-tail x))
```

### Applicative

An applicative wraps an operative. The tag signals the call site to
evaluate arguments before passing them.

```scheme
(define (wrap x)
  (assert (operative? x))
  (make-pair 'applicative x))

(define (applicative? x)
  (and (pair? x) (eq? (pair-head x) 'applicative)))

(define (unwrap x)
  (assert (applicative? x))
  (pair-tail x))
```

---

## `lambda` Desugaring

```scheme
(lambda (x) (+ x 1))
;; desugars to:
(wrap (make-operative (lambda (caller-env x)
                        (values '() (list (+ x 1))))))
```

`wrap` is not special dispatch logic — it is a tag. The call site reads
the tag and decides whether to evaluate arguments.

---

## The Unified Calling Convention

Every combiner is either an operative or an applicative wrapping an operative.
At every call site `(f arg1 arg2 ...)`:

```scheme
(let ((proc (eval f env)))
  (cond
    [(operative? proc)
     ;; pass caller env + unevaluated args as syntax
     ((operative-proc proc) env 'arg1 'arg2 ...)]
    [(applicative? proc)
     ;; evaluate args first, then pass values as syntax to underlying operative
     ((operative-proc (unwrap proc)) env
      (eval 'arg1 env)
      (eval 'arg2 env) ...)]
    [else (error 'call "not a combiner" proc)]))
```

### Return Protocol

Every operative returns two values:

```scheme
(values news out)
;; news — list of (name . value) pairs to introduce into caller scope
;; out  — list of return values
```

### Call Site Unpacking

```scheme
(call-with-values
  (lambda () ((operative-proc proc) env 'arg1 'arg2 ...))
  (lambda (news out)
    (call-with-values
      (lambda () (apply values (map pair-tail news)))
      (lambda (name1 name2 ...)         ;; new bindings in caller scope
        (call-with-values
          (lambda () (apply values out))
          (lambda (result1 result2 ...) ;; return values
            <continuation>))))))
```

Both `news` and `out` are lists unpacked symmetrically via `apply values`.

---

## Example 1 — Operative with Environment Extension

### Source

```scheme
(let ((value 43))
  (define my-vau-proc
    (vau (next add1 . rest) caller-env
      (define caller-env next value)
      (add1 (apply + rest))))
  (display (my-vau-proc summary (lambda (x) (+ x 1)) 40 1))
  (display summary))
```

### Translation

```scheme
(let ((env (env-empty)))
  (let* ((value 43)
         (env (env-extend env 'value value))
         (my-vau-proc
          (make-operative
            (lambda (caller-env next add1 . rest)
              (assert (env? caller-env))
              (values
                (list (make-pair 'next value))
                (list (call-with-values
                        (lambda ()
                          ((operative-proc (unwrap add1))
                           caller-env
                           (apply + rest)))
                        (lambda (_ out) (car out)))))))))
    (call-with-values
      (lambda ()
        ((operative-proc my-vau-proc)
         (env-extend env 'value value)
         'summary                                      ;; next — unevaluated
         (wrap (make-operative                         ;; add1 — wrap(vau)
                 (lambda (caller-env x)
                   (values '() (list (+ x 1))))))
         40 1))                                        ;; rest
      (lambda (news out)
        (call-with-values
          (lambda () (apply values (map pair-tail news)))
          (lambda (summary)                            ;; next → summary
            (call-with-values
              (lambda () (apply values out))
              (lambda (result)
                (display result)    ;; 42
                (display summary)   ;; 43
                ))))))))
```

---

## Example 2 — Unknown Combiner at Call Site (datarama's case)

### Source

```scheme
(define (foo bar)
  (bar (+ 2 2)))

(foo quote)                       ;; => (+ 2 2)
(foo (lambda (x) (+ x x)))       ;; => 8
```

### Translation

`bar` is a lambda parameter — combiner status unknown at compile time.
The call site must dispatch at runtime:

```scheme
(let ((foo
       (wrap
         (make-operative
           (lambda (caller-env bar)
             (assert (env? caller-env))
             (values '()
               (list
                 (cond
                   [(operative? bar)
                    (call-with-values
                      (lambda ()
                        ((operative-proc bar) caller-env '(+ 2 2)))
                      (lambda (_ out) (car out)))]
                   [(applicative? bar)
                    (call-with-values
                      (lambda ()
                        ((operative-proc (unwrap bar))
                         caller-env
                         (+ 2 2)))              ;; evaluated
                      (lambda (_ out) (car out)))]
                   [else (error 'foo "not a combiner" bar)]))))))))
  ...)
```

The `(+ 2 2)` is preserved as unevaluated syntax for operatives and
evaluated to `4` for applicatives. The dispatch is explicit and
unavoidable — `bar`'s type is unknown until runtime.

---

## Example 3 — `while` / `:=` (Walrus)

### Source

```scheme
(let ((f (make-file '("hello" " " "world" "!"))))
  (while (:= chunk (file-read f))
    (display chunk)))
```

`:=` evaluates its expression, introduces the binding via `%news`,
and returns the value as the test. `while` loops until the test is `#f`.

```scheme
(define :=op
  (make-operative
    (lambda (caller-env name expr)
      (assert (env? caller-env))
      (let ((val (eval expr caller-env)))
        (values
          (list (make-pair name val))    ;; news: introduce name
          (list val))))))           ;; out: value as test

(define while-op
  (make-operative
    (lambda (caller-env test body)
      (assert (env? caller-env))
      (let loop ()
        (call-with-values
          (lambda ()
            ((operative-proc :=op) caller-env
             (pair-head test)            ;; name: chunk
             (pair-tail test)))          ;; expr: (file-read f)
          (lambda (news out)
            (let ((val (car out)))
              (when val
                (call-with-values
                  (lambda () (apply values (map pair-tail news)))
                  (lambda (chunk)
                    (eval body (env-extend caller-env 'chunk chunk))
                    (loop)))))))))))
```

---

## Example 4 — `wrap` Desugaring

```scheme
(lambda (x) (+ x 1))
;; is:
(wrap (make-operative (lambda (caller-env x) (values '() (list (+ x 1))))))
```

At call site `(add1 40)`:

- `add1` is `applicative?` → evaluate `40` → pass `40` to underlying operative
- operative body receives `caller-env` and `40`
- returns `(values '() (list 41))`

`wrap` is a tag, not special logic. The call site reads the tag.

---

## Dependencies

- **match.scm** (SRFI-241 pattern matcher): Local copy at `../../match.scm`.
  The compiler uses `match` extensively throughout all passes. Catamorphic
  patterns like `,[var]` auto-recurse, used in passes where the environment
  does not change. Binding forms (let/letrec/vau) use explicit recursion
  because they extend the environment.

---

## Compiler Architecture (Nanopass, 5 Passes)

```
Source S-expr
  │
  ├── Pass 1: parse         S-expr → L1 AST
  │     lambda → (wrap (vau params #f body))
  │     define (3-arg) → (define <env> <name> <val>)
  │
  ├── Pass 2: annotate      L1 → L2
  │     (var name) → (var name local|free)
  │
  ├── Pass 3: classify      L2 → L3
  │     (wrap (vau p #f body)) → (lam p body)  when pure
  │     genuine operatives stay as (vau ...)
  │
  ├── Pass 4: bta           L3 → L4
  │     annotate vau params: static-eval | static-syntax | dynamic
  │
  └── Pass 5: codegen       L4 → Chez Scheme
        known vau calls → compile-time specialization (Futamura)
        unknown calls   → runtime operative/applicative dispatch
        define nodes    → call-with-values (values news out) protocol
```

---

## L1 AST Grammar

```
AST = (const <value>)                     ; number, boolean, string, null
    | (var <name>)                        ; symbol reference
    | (quot <datum>)                      ; quoted datum
    | (if <AST> <AST> <AST>)             ; conditional (always 3-arm)
    | (begin <AST> ...)                   ; sequencing
    | (let ((<name> <AST>) ...) <AST>)   ; local binding
    | (let <name> ((<name> <AST>) ...) <AST>) ; named let (loop)
    | (letrec ((<name> <AST>) ...) <AST>); recursive binding
    | (vau <params> <ep> <AST>)          ; operative
    | (wrap <AST>)                        ; applicative wrapper
    | (eval <AST> <AST>)                 ; explicit evaluation
    | (call <AST> (<AST> ...))           ; application
    | (dyn-env)                          ; dynamic calling environment
    | (define <AST> <AST> <AST>)        ; inject binding into target env

ep = #f        ; ignored (canonical form for _ and %ignore)
   | <symbol>  ; live environment parameter
```

---

## Environment Extension Protocol (`define`)

`define` supports destructuring. The four forms are:

```scheme
(define name expr)              ;; simple binding (implicit current env)
(define (names ...) expr)       ;; destructuring binding (implicit current env)
(define env name expr)          ;; simple binding into explicit env
(define env (names ...) expr)   ;; destructuring binding into explicit env
```

A `(define env name value)` form inside a vau body introduces a new
binding into the caller's scope. The compilation strategy:

1. The operative accumulates `(name . value)` pairs locally into `%news`
2. Returns `(values news out)` — news is the accumulated list, out is the result
3. The call site unpacks via nested `call-with-values`
4. New names land as lambda parameters — immutable by construction

This works when the export list is **statically known** in the syntax.
For dynamically computed export lists, fall back to `seed-eval`.

### Inside Operative Body (compiled)

```scheme
;; (define env x 42) compiles to:
(let ([v 42])
  (set! env (cons (cons 'x v) env))   ;; local mutation only
  (set! %news (cons (cons 'x v) %news))
  v)
```

`set!` here mutates *local variables* — `env` and `%news` are the
operative's own private copies. No one else holds a reference.

### At Call Site (generated by codegen-begin)

```scheme
(call-with-values
  (lambda ()
    (values (list val1 val2 ...)       ;; news values
            (list result1 result2 ...))) ;; out values
  (lambda (news out)
    (call-with-values
      (lambda () (apply values news))
      (lambda (name1 name2 ...)        ;; new bindings — lambda params
        (call-with-values
          (lambda () (apply values out))
          (lambda (result1 result2 ...) ;; return values
            <continuation>))))))
```

---

## Compiler Context (`ctx`)

The codegen pass threads a context alist:

| Value | Meaning |
|-------|---------|
| `'direct` | Pure lambda — call as `(name args...)` |
| `(vau-info params ep body)` | Known operative — specialize at call site |
| `'scheme-var` | Lambda-bound Chez variable |
| `'(%has-env . #t)` | Inside a vau body with live env param |
| `'(%has-news . #t)` | Inside a vau body that uses `define` |

---

## Static vs Dynamic Dispatch

There is no hardcoded `*primitives*` list. All dispatch decisions come
from what the compiler knows via binding context (`ctx`).

| Call site | Condition | Generated code |
|-----------|-----------|----------------|
| Known `lam` | `ctx` entry is `direct` | `(name args...)` |
| Known `vau` | `ctx` entry is `vau-info` | specialize body at compile time |
| Unknown local | lambda parameter, not in `ctx` | runtime dispatch |
| Unknown free | not in `ctx` | runtime dispatch |

Runtime dispatch template:

```scheme
(let ([proc name])
  (if (and (pair? proc) (eq? (car proc) 'operative))
      ((cdr proc) env 'arg1 'arg2 ...)    ;; operative path
      (proc arg1 arg2 ...)))              ;; applicative path
```

---

## Partial Evaluation (First Futamura Projection)

For statically known `vau` calls, the compiler specializes the body
at compile time — eliminating the operative entirely from the output.

```scheme
;; Source:
(letrec ((and2 (vau (a b) e (if (eval a e) (eval b e) #f))))
  (and2 div3 div7))

;; Compiled (and2 fully eliminated):
(if div3 div7 #f)
```

This is equivalent to what `syntax-rules` produces.

Key rules during specialization (`spec`):

- `(eval (var param local) (var ep local))` where param in subst → compile the arg directly
- `(var param local)` where param in subst → quote as syntax
- `(var ep local)` → `(dyn-env)`
- `(eval <expr> (var ep local))` → `(seed-eval <spec'd-expr> env)` fallback

---

## Known Limitations

### Dynamically Computed Export Lists

```scheme
;; This cannot be statically compiled:
(provide (compute-names-at-runtime) ...)
;; → falls back to seed-eval
```

### First-Class Operatives Through Lambda Parameters

```scheme
;; datarama's case — dispatch is correct but argument evaluation
;; is committed before the operative is identified:
(define (foo bar) (bar (+ 2 2)))
(foo my-quote)  ;; runtime dispatch handles this correctly
```

When `bar` is passed through a lambda parameter, the call site
emits runtime dispatch. The compiler cannot specialize at compile time.

---

## Environments: `env-empty` vs `environment-ground`

There are two distinct environments:

- **`env-empty`** — the blank environment used during compilation. The
  compiler threads this through passes to track bindings statically.

- **`environment-ground`** — a runtime alist of Chez Scheme-backed
  primitives, provided to `seed-eval` when the compiler cannot
  eliminate an `eval` call statically. Contains:
  - Arithmetic: `+ - * / = < > <= >=`
  - List: `cons car cdr list append reverse length map apply for-each`
  - Predicates: `null? pair? number? boolean? string? symbol? eq? equal?`
  - I/O: `display newline`
  - Operatives: `quote if begin when unless`
  - Special: `make-encapsulation-type` (disjoint type constructor)

**Design goal**: the compiler should handle enough cases statically
that `environment-ground` + `seed-eval` become a rare escape hatch,
not a load-bearing path. Most seed3 programs should compile down to
direct Chez Scheme with no interpreter fallback.

---

## `seed-eval` Fallback

For dynamically constructed code and the `eval` form, a Scheme
interpreter provides the fallback:

```scheme
(define (seed-eval expr env)
  (match expr
    [,s (guard (symbol? s)) (env-ref-unbox s env)]
    [(quote ,d) d]
    [(if ,t ,c ,a) (if (seed-eval t env) (seed-eval c env) (seed-eval a env))]
    [(vau ,params ,ep ,body) (make-operative ...)]
    [(lambda ,params ,body) (wrap (make-operative ...))]
    [(,op . ,args) ;; operative/applicative dispatch
     ...]))
```

`seed-eval` is the interpreter fallback path, not the primary
compilation target. The goal is to eliminate `seed-eval` call sites
progressively as the compiler handles more cases statically. A seed3
program that compiles with zero `seed-eval` residuals runs at native
Chez Scheme speed.

---

## Benchmark Targets

The compiler's correctness and performance are validated against:

| Benchmark | What it exercises |
|-----------|-------------------|
| N-Queens | Pure lambda / letrec — no operatives |
| Collatz | Simple `vau` macros (`and2`, `or2`) |
| Abacus | SRFI-241 `match` catamorphism as `vau` |
| Abacus2 | Ellipsis patterns in `match` |
| Gremlin-fold | `gremlin-fold` vau vs `syntax-rules` |
| Gremlin-pipeline | Recursive `vau` DSL vs `syntax-case` |

Target: Seed compiled output ≈ native Chez Scheme performance on all benchmarks.
Current result: Seed2 6% faster overall than native Chez on the full suite.

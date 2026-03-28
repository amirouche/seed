# Walrus: seed-eval / compiled Chez interop

The walrus example (`walrus.seed2.scm`) compiles and produces correct
compiled output but fails at runtime.  The root cause is a mismatch
between the two environment representations used by compiled code and
`seed-eval`.

## What works

The `if`-based version of `while:=` works:

```scheme
(define while:=
  (vau (var sep expr . body) env
    (let loop ()
      (let ((val (eval expr env)))
        (if val
          (begin (define env var val)
                 (for-each (lambda (e) (eval e env)) body)
                 (loop))
          (void))))))
```

Here `if` is compiled directly.  The compiler handles `define env`,
`for-each`, and `loop` as Chez code — no runtime dispatch needed.

## What fails

Replacing `if` with `when` (an operative in `ground-env`):

```scheme
(when val
  (define env var val)
  (for-each (lambda (e) (eval e env)) body)
  (loop))
```

`when` is resolved via `env-ref` at runtime.  The operative dispatch
passes its arguments as quoted syntax to `seed-eval`.  This triggers
two interop gaps:

### Gap 1: Specializer mangles syntax args

When the specializer inlines the vau call at the call site, it
substitutes vau parameters into the syntax arguments:

- `var` (bound to `chunk`) becomes `'chunk` — a quoted form where
  `(define env ...)` expects a bare symbol
- `body` (bound to `((display chunk))`) gets double-quoted

**Current fix:** `has-unknown-operative-calls?` guard on codegen's vau
specialization.  When the vau body contains calls to free non-primitive
symbols (potential operatives), skip compile-time specialization and
fall through to the runtime operative path.

### Gap 2: Two env representations collide

Compiled Chez code uses **mutable alists** — `(define env var val)` is
compiled to `set-car!/set-cdr!` mutations on the env cons cell.

`seed-eval-stmt` uses **immutable threading** — `(define name val)`
returns `(values v (cons (cons name v) env))`, building a new env.

When an operative like `when` processes body forms via `seed-eval-stmt`,
the `(define env var val)` form mutates the target alist (found by
resolving the symbol `env`), but `seed-eval-stmt`'s threaded env is a
separate copy.  Subsequent forms like `(for-each ... body)` create
lambdas that capture the symbol `env`, which resolves to the mutated
alist — but that alist and the threaded env disagree about which
bindings exist.

Result: `chunk` is defined in one representation but not found in the
other → `env-ref-unbox: unbound with irritant chunk`.

## Fixes applied so far

These fixes are in `seed2.scm` and enable all non-walrus tests:

1. **Operative dispatch in codegen** — local/free variable calls emit
   `(if (operative? proc) ...)` runtime dispatch instead of assuming
   all callees are applicatives.

2. **Env extension at dispatch sites** — before calling an operative,
   extend `env` with Chez locals from `ctx` that appear in the syntax
   args, so `seed-eval` can resolve them.

3. **`when`/`unless`/`eval`/`set!` in ground-env** — runtime
   operatives and procedures needed by `seed-eval` when processing
   syntax args from compiled vau bodies.

4. **`has-unknown-operative-calls?` guard** — skip vau specialization
   when the body calls potential operatives, avoiding syntax arg
   mangling.

5. **3-arg `define` in `seed-eval-stmt`** — thread env correctly when
   `(define env name val)` appears in `seed-eval-stmt` body forms.

## Path forward

The fundamental issue is that `(define env var val)` is a compile-time
form that assumes mutable alist operations.  When it appears inside
syntax args processed by `seed-eval`, the mutation and threading models
conflict.

Possible approaches:

- **Unify env representation**: make `seed-eval` use the same mutable
  alist as compiled code, so `(define env var val)` mutations are
  visible to all subsequent forms without needing immutable threading.
- **Compile syntax args instead of interpreting them**: instead of
  passing quoted forms to `seed-eval`, compile the operative's body
  forms to Chez code that runs in the correct scope.  This is
  essentially the `compile-eval-body` TODO.

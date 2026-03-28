# Kernel Dialect of Scheme Considered Helpful

## What

I have been impressed by Kernel, created by John Nathan Shutt, for several years. I tried to let it go, but it came back into my life, much like Python, JavaScript, or PHP, but without the same elegance or attitude. Perhaps it is elitism, or perhaps it is intellectual curiosity and possibly tribalism. Maybe it is the parentheses. I am repeating myself.

Kernel bridges almost 70 years of history. Lisp started in 1958 at MIT, Scheme branched off in 1975, Brian Cantwell Smith's 1982 thesis on 3-Lisp is the intellectual ancestor of everything Kernel does with reified environments, and Common Lisp crystallized another branch in the Symbolics era. The ideas never stopped spreading — Femtolisp powers Julia's parser, Clojure's edn brought s-expression data notation to a mainstream audience, Fennel found traction in game development. What these share is the recurring discovery that a small, programmable core pays off. Kernel's `vau` is the next idea in that lineage waiting to land: the unification of macros and procedures.

[John Nathan Shutt](https://web.cs.wpi.edu/~jshutt/) managed to crystallize with brilliance and likely formal accuracy the work of the entire Lisp community since its early days with the release of the SINK interpreter and the last draft of specification for [Kernel programming language](https://web.cs.wpi.edu/~jshutt/kernel.html) in particular [Revised -1 Report on the Kernel Programming Language](https://ftp.cs.wpi.edu/pub/techreports/pdf/05-07.pdf) in 2009. He supported his thesis [Fexprs as the basis of Lisp function application or `$vau` : the ultimate abstraction](https://web.cs.wpi.edu/~jshutt/dissertation/etd-090110-124904-Shutt-Dissertation.pdf) in 2010. He passed away in 2020. 

He was not the only one to believe in the ideas that are in Kernel. For example, first-class environments are found in MIT Scheme and Guile. I think I remember that Gambit has reified continuations (and more), and continuation attachments came to Chez Scheme, a device similar to keyed dynamic variables from Kernel. Gambit (again!) has had them under a different guise for much longer. So, Kernel, like any other Lisp, is a Lisp.

The thing that got me hooked on Kernel, despite my passion for code, was laziness. Despite the excellent work to document syntax rules and syntax-case such as the work of [“Extending a Language — Writing Powerful Macros in Scheme” by Marc Nieper-Wißkirchen](https://github.com/mnieper/scheme-macros), I do not subscribe to this approach. I prefer Kernel’s `vau`. I like the idea of unifying macros and procedures so you don't need two separate metalinguistic systems, one mechanism instead of two.

However, vau was cursed. [In 1998, Wand, "The Theory of Fexprs is Trivial," ACM SIGPLAN Notices 33(9), 1998.](https://www.ccs.neu.edu/home/wand/pubs.html#Wand98) proved that [fexpr](https://en.wikipedia.org/wiki/Fexpr) make equational reasoning impossible because you cannot substitute equals for equals when you don’t know if an expression will be evaluated. Compilation was considered intractable. 

Until 2026. 

EDIT (2026-02-06): I was pointed to kraken-lang.org and in particular
[Practical compilation of fexprs using partial evaluation: Fexprs can
performantly replace macros in purely-functional
Lisp](https://arxiv.org/abs/2303.12254). The difference between Kraken
and seed, is that seed is not purely functional, seed support
`define`, and `set!` but not on dynamic environments, also `seed` is
an extension of chezscheme.

## How

Making `vau`’s dynamic environment immutable restores enough static knowledge to compile competitively. In standard Kernel, a `vau` operative receives the caller's dynamic environment as first-class value; it can read it, traverse it, and crucially, mutate it. That last power is what kills compilation. If any operative can rewrite the caller's bindings at any time, the compiler cannot know what any variable means at any call site, so it cannot substitute, inline, or optimize anything. The fix is surgical: pass the environment, but make it read-only. The operative can still introspect the caller's bindings, that is the whole point of `vau`, the ability to decide whether and how to evaluate its arguments, but it cannot side-effect them. In practice, it can't define, or set! a variable in the dynamic environment, hence there is no mutation, no new bindings. Concretely, in the compiler, each operative call passes the environment as the first element of a `(env . args)` pair. The environment is a value, not a mutable store. That single constraint — immutability — gives the compiler back enough static knowledge to reason about the code, inline calls, and emit the same quality of native code that Chez Scheme produces from syntax-case.

Catamorphism vs. syntax-case. Consider a small expression evaluator. In Scheme with syntax-case, you write a macro that pattern-matches at compile time, then a separate runtime function that walks the tree with car, cdr, and cond. Two mechanisms, two languages — the macro language and the runtime language — kept apart by design. In Kernel, `vau` with `match` does both in one shot. The `match` clause `(+ ,a ,b)` binds `a` and `b` and recurses when the comma signals a catamorphism, meaning the transformation applies to subexpressions automatically before the clause body sees them. No explicit recursive calls, no peeling apart list structure by hand. The Scheme version is more verbose not because the programmer is less skilled, but because the language forces the separation of two concerns that are, structurally, the same concern: tree-in, tree-out transformation. Readability is subjective; the reader can judge for themselves. Performance is not.

## Developer Experience

vau does not require learning a new DSL, the pattern matching domain specific language of syntax-rules, and the shenanigans of syntax-object-fu of `syntax-case`. All three implementation implement the same behavior, only the last, using `vau` is economical:

```scheme
;;; myor — three implementations of short-circuit OR
;;;
;;; The point: vau controls evaluation directly.
;;; syntax-rules and syntax-case generate code that controls evaluation.
;;; Same result. One is a program. The other two are programs that write programs.

;;; -------------------------------------------------------
;;; 1. syntax-rules (R5RS / R7RS)
;;;
;;; The macro language: pattern templates with ellipsis.
;;; Short-circuit requires a let-binding to avoid double
;;; evaluation — the template language has no way to
;;; "evaluate once and test," so it must generate code
;;; that does it at runtime.
;;; -------------------------------------------------------

(define-syntax myor
  (syntax-rules ()
    ((_) #f)
    ((_ e) e)
    ((_ e1 e2 ...)
     (let ((t e1))
       (if t t (myor e2 ...))))))

;;; -------------------------------------------------------
;;; 2. syntax-case (R6RS / Chez Scheme)
;;;
;;; More power: you can run arbitrary Scheme at expand time.
;;; But for this example, the extra power buys nothing —
;;; the structure is identical to syntax-rules. The reader
;;; still operates in two languages: the template language
;;; (#' quotes, ellipsis) and the runtime language.
;;; -------------------------------------------------------

(define-syntax myor
  (lambda (x)
    (syntax-case x ()
      ((_) #'#f)
      ((_ e) #'e)
      ((_ e1 e2 ...)
       #'(let ((t e1))
           (if t t (myor e2 ...)))))))

;;; -------------------------------------------------------
;;; 3. vau (Kernel / Seed)
;;;
;;; No template language. No phase separation. No ellipsis.
;;; The operative receives its arguments unevaluated and
;;; the caller's environment. It decides what to evaluate,
;;; when, and how many times — using ordinary code.
;;;
;;; The let-binding that syntax-rules must generate?
;;; Here it is just... a let-binding. Written by the
;;; programmer, not generated by a macro expander.
;;; -------------------------------------------------------

(define myor
  (vau args env
    (if (null? args) #f
      (let ((v (eval (car args) env)))
        (if v v
          (eval (cons myor (cdr args)) env))))))

;;; -------------------------------------------------------
;;; Usage — identical in all three:
;;;
;;;   (myor #f #f 42)       => 42
;;;   (myor #f #f #f)       => #f
;;;   (myor 1 (error "!"))  => 1  (second arg never evaluated)
;;; -------------------------------------------------------
```

## Benchmarks

```bash
# make-benchmark.sh
── N-Queens — exercising single CPU ──────────────────────────────
  scheme --script seedink.scm n-queen.seed    compile:      n/as  execute: 22.988239534s  wall:   23.598s
  scheme --script n-queen.scm                                    execute:   23.003s  wall:   23.398s

── Collatz — exercising syntax-rules ────────────────────────────
  scheme --script seedink.scm collatz.seed    compile:      n/as  execute: 9.995808085s  wall:   10.263s
  scheme --script collatz.scm                                    execute:   10.307s  wall:   10.342s

── Abacus — exercising syntax-case ───────────────────────────────
  scheme --script seedink.scm abacus.seed     compile:      n/as  tree: 1.174771122s  eval: 1.649855682s  wall:    3.356s
  scheme --script abacus.scm                                      tree:    1.259s  eval:    1.560s  wall:    3.108s

── Abacus2 — multi-operand match (ternary trees) ─────────────────
  scheme --script seedink.scm abacus2.seed    compile:      n/as  tree: 0.803791520s  eval: 3.897080440s  wall:    5.337s
  scheme --script abacus2.scm                                     tree:    0.810s  eval:    5.441s  wall:    6.879s

── Summary ────────────────────────────────────────────────────────
Benchmark             Driver              Monotonic    Wall Clock
────────────────────  ───────────────  ────────────  ────────────
N-Queens              seedink               22.988s       23.598s
N-Queens              scheme                23.003s       23.398s
Collatz               seedink                9.996s       10.263s
Collatz               scheme                10.307s       10.342s
Abacus                seedink                2.825s        3.356s
Abacus                scheme                 2.819s        3.108s
Abacus2               seedink                4.701s        5.337s
Abacus2               scheme                 6.251s        6.879s
────────────────────  ───────────────  ────────────  ────────────
TOTAL                 seedink               40.510s       42.554s
TOTAL                 scheme                42.381s       43.727s
```

## Feedback & Further Reading

This project was discussed on [r/scheme](https://old.reddit.com/r/scheme/comments/1r2v4ax/kernels_vau_can_be_faster_than_syntaxcase/) and the following points were raised:

**On `define-record-type` and environment mutation** — WittyStick pointed out that `$provide!` is the canonical Kernel solution, and that compiling operatives with environment mutation is possible via row-polymorphic environment types. Seed2 now supports caller environment extension via `call-with-values` — the exported names land as lambda parameters, immutably. The old downside ("you can't write `define-class`") no longer holds when the export list is statically known.

[**On first-class operatives as function parameters** — datarama
identified a genuine
bug](https://lobste.rs/s/2debab/seed_adding_vau_with_immutable_dynamic#c_u7wldl):
call sites for lambda-bound parameters do not currently emit
operative/applicative dispatch. This is a known issue.

**References from the thread:**

- Mitchell Wand, [Type Inference for Record Concatenation and Multiple Inheritance](https://www.cs.tufts.edu/~nr/cs257/archive/mitch-wand/types-simple-objects.pdf) — the theoretical basis for row-polymorphic environments
- Alan Bawden, [First-class Macros Have Types](https://people.csail.mit.edu/alan/mtt/) — static typing for first-class macros, directly relevant to compile-time environment shape inference

## Conclusion

Here is the Chez Scheme code. Benchmark! Enjoy! And let there be… evaluation.

## Disclaimer

The implementation was developed with Claude.AI as a coding assistant. I directed the design and reviewed the code. This is exploratory work — a proof of concept for intellectual curiosity, not production infrastructure.

Claude is AI and I can make mistakes. Please double-check anything.

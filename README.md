# Kernel Dialect of Scheme Considered Helpful

## What

I have been impressed by Kernel, created by John Nathan Shutt, for several years. I tried to let it go, but it came back into my life, much like Python, JavaScript, or PHP, but without the same elegance or attitude. Perhaps it is elitism, or perhaps it is intellectual curiosity and possibly tribalism. Maybe it is the parentheses. I am repeating myself.

Kernel bridges almost 70 years of history. Lisp started in 1958 at MIT, Scheme branched off in 1975, Brian Cantwell Smith's 1982 thesis on 3-Lisp is the intellectual ancestor of everything Kernel does with reified environments, and Common Lisp crystallized another branch in the Symbolics era. The ideas never stopped spreading — Femtolisp powers Julia's parser, Clojure's edn brought s-expression data notation to a mainstream audience, Fennel found traction in game development. What these share is the recurring discovery that a small, programmable core pays off. Kernel's `vau` is the next idea in that lineage waiting to land: the unification of macros and procedures.

I also need to mention the HN famous [Femtolisp](https://news.ycombinator.com/item?id=22094722) (2020) and [Data notation in Clojure](https://news.ycombinator.com/item?id=27685875) (2021), and the currently most popular lisp for creating games [Why Fennel?](https://news.ycombinator.com/item?id=43673551) (2025). You have a good picture of how what follows can land, resonate and percolate in the broad computer industry.

[John Nathan Shutt](https://web.cs.wpi.edu/~jshutt/) managed to crystallize with brilliance and likely formal accuracy the work of the entire Lisp community since its early days with the release of the SINK interpreter and the last draft of specification for [Kernel programming language](https://web.cs.wpi.edu/~jshutt/kernel.html) in particular [Revised -1 Report on the Kernel Programming Language](https://ftp.cs.wpi.edu/pub/techreports/pdf/05-07.pdf) in 2009. He supported his thesis [Fexprs as the basis of Lisp function application or `$vau` : the ultimate abstraction](https://web.cs.wpi.edu/~jshutt/dissertation/etd-090110-124904-Shutt-Dissertation.pdf) in 2010. He passed away in 2020. 

He was not the only one to believe in the ideas that are in Kernel. For example, first-class environments are found in MIT Scheme and Guile. I think I remember that Gambit has reified continuations (and more), and continuation attachments came to Chez Scheme, a device similar to keyed dynamic variables from Kernel. Gambit (again!) has had them under a different guise for much longer. So, Kernel, like any other Lisp, is a Lisp.

The thing that got me hooked on Kernel, despite my passion for code, was laziness. Despite the excellent work to document syntax rules and syntax-case such as the work of [“Extending a Language — Writing Powerful Macros in Scheme” by Marc Nieper-Wißkirchen](https://github.com/mnieper/scheme-macros), I do not subscribe to this approach. I prefer Kernel’s `vau`. I like the idea of unifying macros and procedures so you don't need two separate metalinguistic systems, one mechanism instead of two.

However, vau was cursed. [In 1998, Wand, "The Theory of Fexprs is Trivial," ACM SIGPLAN Notices 33(9), 1998.](https://www.ccs.neu.edu/home/wand/pubs.html#Wand98) proved that [fexpr](https://en.wikipedia.org/wiki/Fexpr) make equational reasoning impossible because you cannot substitute equals for equals when you don’t know if an expression will be evaluated. Compilation was considered intractable. Until 2026. 

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

- **N-Queens** (n=14): Backtracking search counting all solutions to the 14-queens problem. Pure lambda code with list allocation, higher-order functions (map, apply, append), and deep recursion. Tests raw compiled code performance with no vau involvement.

- **syntax-rules** (Collatz ≤ 20,000,000 | Special ≤ 40,000,000): Two numeric loops using `and2`/`or2` short-circuit operators. Seed implements these as `vau` operatives that are specialized at compile time. Chez uses `syntax-rules` macros. Tests vau-as-macro against hygienic pattern macros.

- **syntax-case** (Collatz ≤ 20,000,000 | Special ≤ 40,000,000): Same workload as syntax-rules, but the Chez baseline uses `syntax-case` procedural macros instead of `syntax-rules`. Tests vau-as-macro against procedural macros.

- **Abacus** (bal-depth=27): Arithmetic expression evaluator using `match` with catamorphism patterns (`,[x]`) and guard clauses. Evaluates a balanced binary tree of 134,217,728 additions. Tests compiled pattern matching performance after alist fusion.

## Parameters

N-Queens n=14 | Collatz ≤ 20,000,000 | Special ≤ 40,000,000 | Abacus bal-depth=27

| Benchmark | Runner | Compile | Execute | Total | Wallclock | RSS (MB) | Ratio |
|---|---|---:|---:|---:|---:|---:|---:|
| N-Queens | seed2 | 0.000s | 18.336s | 18.336s | 18.54s | 1880 | |
| | chez | n/a | 19.699s | 19.699s | 19.78s | 1988 | 0.93x |
| syntax-rules | seed2 | 0.000s | 11.161s | 11.161s | 11.34s | 48 | |
| | chez | n/a | 10.636s | 10.636s | 10.66s | 48 | 1.05x |
| syntax-case | seed2 | 0.000s | 11.184s | 11.184s | 11.36s | 48 | |
| | chez | n/a | 10.635s | 10.635s | 10.66s | 48 | 1.05x |
| Abacus | seed2 | 0.001s | 13.463s | 13.464s | 13.53s | 11255 | |
| | chez | n/a | 13.871s | 13.871s | 14.01s | 8693 | 0.97x |

Ratio = seed execute / chez execute (lower is better, 1.00x = parity)

## Conclusion

Here is the Chez Scheme code. Benchmark! Enjoy! And let there be… evaluation.

## Disclaimer

The implementation was developed with Claude.AI as a coding assistant. I directed the design and reviewed the code. This is exploratory work — a proof of concept for intellectual curiosity, not production infrastructure.

Claude is AI and I can make mistakes. Please double-check anything.

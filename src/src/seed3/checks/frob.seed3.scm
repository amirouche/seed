;; Test: operative that both extends caller env and returns a value.
;; frob defines a binding (a*) in the caller env and returns a separate
;; computed value, exercising the (values news out) dual-return path.
(define frob (vau (a a*) env
  (define env a* (+ 40 2 (eval a env)))
  (+ 40 1 (eval a env))))
(display (frob 1 next))
(newline)
(display next)
(newline)

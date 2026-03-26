;; Test: simple single-binding operative with eval.
;; my-def evaluates its value argument and injects the result into
;; the caller env. Verifies chained defines where y depends on x.
(define my-def (vau (name val) e
  (define e name (eval val e))))
(my-def x 42)
(my-def y (+ x 1))
(display x)
(display " ")
(display y)
(newline)

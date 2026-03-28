;; Test: single-define operative at statement level.
;; The operative defines one binding and returns a different value.
;; Verifies the define is visible via (values news out) convention.
(define my-op (vau (x) env
  (define env x (+ 40 2))
  (+ 40 1)))

(my-op dummy)
(display dummy)
(newline)

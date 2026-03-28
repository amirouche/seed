;;; aif.seed2 — Hygienic anaphoric if via vau
;;;
;;; (aif var expr consequent alternative)
;;;
;;; Evaluates expr.  If truthy, binds the result to var in the
;;; caller's scope and evaluates consequent.  Otherwise evaluates
;;; alternative.  var is visible in consequent but NOT in
;;; alternative — proper hygiene.
;;;
;;; In Scheme this requires syntax-case + datum->syntax to break
;;; hygiene for the anaphoric variable.  In Seed2 it's 3 lines:
;;; a vau that uses (define env var val) to inject the binding.

(define aif
  (vau (var test-expr then-expr else-expr) env
    (let ((val (eval test-expr env)))
      (if val
          (begin
            (define env var val)
            (eval then-expr env))
          (eval else-expr env)))))

;; ── Examples ──

(display "--- aif examples ---")
(newline)

;; Basic: it binds the truthy value
(aif it (memv 3 '(1 2 3 4 5))
  (begin (display "found: ") (display it) (newline))
  (display "not found\n"))

;; it is the result of the test, not just #t
(aif it (assq 'b '((a . 1) (b . 2) (c . 3)))
  (begin (display "value: ") (display (cdr it)) (newline))
  (display "no entry\n"))

;; False case: else branch runs
(aif it #f
  (display "never\n")
  (display "false branch\n"))

;; Nested: inner it shadows outer it
(aif it (assq 'x '((x . 42)))
  (begin
    (display "outer it: ") (display (cdr it)) (newline)
    (aif it (assq 'y '((y . 99)))
      (begin (display "inner it: ") (display (cdr it)) (newline))
      (display "not found\n")))
  (display "not found\n"))

;; Different binding name — user chooses
(aif result (* 6 7)
  (begin (display "result: ") (display result) (newline))
  (display "never\n"))

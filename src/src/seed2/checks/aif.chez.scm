;;; aif.scm — Hygienic anaphoric if via syntax-rules
;;;
;;; Chez Scheme equivalent of aif.seed2.
;;;
;;; (aif var expr consequent alternative)
;;;
;;; Since the user names the binding variable explicitly,
;;; plain syntax-rules suffices — no datum->syntax needed.
;;;
;;; Compare with Seed2:
;;;   Seed2: vau + (define env var val) — runtime code, compiler-specialized
;;;   Chez:  syntax-rules pattern rewrite — compile-time expansion

(define-syntax aif
  (syntax-rules ()
    [(_ var test-expr then-expr else-expr)
     (let ([var test-expr])
       (if var then-expr else-expr))]))

;; ── Examples (same as aif.seed2) ──

(display "--- aif examples ---")
(newline)

(aif it (memv 3 '(1 2 3 4 5))
  (begin (display "found: ") (display it) (newline))
  (display "not found\n"))

(aif it (assq 'b '((a . 1) (b . 2) (c . 3)))
  (begin (display "value: ") (display (cdr it)) (newline))
  (display "no entry\n"))

(aif it #f
  (display "never\n")
  (display "false branch\n"))

(aif it (assq 'x '((x . 42)))
  (begin
    (display "outer it: ") (display (cdr it)) (newline)
    (aif it (assq 'y '((y . 99)))
      (begin (display "inner it: ") (display (cdr it)) (newline))
      (display "not found\n")))
  (display "not found\n"))

(aif result (* 6 7)
  (begin (display "result: ") (display result) (newline))
  (display "never\n"))

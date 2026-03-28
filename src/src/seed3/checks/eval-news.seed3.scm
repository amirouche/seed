;; Test: seed-eval begin threads env through operative calls.
;; A compiled operative returns (values news result); seed-eval's
;; begin handler must thread the news into env so that subsequent
;; expressions in the same begin can see the defined bindings.
(define my-def (vau (name val-expr) env
  (define env name (eval val-expr env))))

;; Eval a begin where later expressions depend on earlier operative defs.
;; x=42, y=(+ x 1)=43, result=(+ x y)=85
(define test-eval (vau () env
  (eval '(begin
           (my-def x 42)
           (my-def y (+ x 1))
           (+ x y))
        env)))

(display (test-eval))
(newline)

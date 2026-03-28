;; Test: operative that defines multiple bindings in the caller env.
;; Verifies that both x and y are visible after (setup) via the
;; (values news out) convention with multiple env additions.
(define setup (vau () env
  (define env x 42)
  (define env y 99)))
(setup)
(display x)
(display " ")
(display y)
(newline)

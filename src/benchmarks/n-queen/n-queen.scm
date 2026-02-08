(library (benchmarks n-queen n-queen)
  (export run-benchmark)
  (import (chezscheme))

(define (list-tabulate n proc)
  (let loop ((i (- n 1)) (acc '()))
    (if (< i 0) acc (loop (- i 1) (cons (proc i) acc)))))

(define (n-queens n)
  (letrec
      ((place-initial-row
        (lambda ()
          (list-tabulate n (lambda (col) (list (cons 0 col))))))
       (invalid?
        (lambda (soln-so-far row col)
          (exists (lambda (posn)
                    (or (= col (cdr posn))
                        (= (abs (- row (car posn)))
                           (abs (- col (cdr posn))))))
                  soln-so-far)))
       (place-on-row
        (lambda (soln-so-far row)
          (let try-col ((col 0) (res '()))
            (if (= col n) res
                (try-col (+ 1 col)
                         (if (invalid? soln-so-far row col) res
                             (cons (cons (cons row col) soln-so-far)
                                   res)))))))
       (solve
        (lambda (res row)
          (if (= row n) res
              (solve (apply append
                            (map (lambda (soln) (place-on-row soln row))
                                 res))
                     (+ 1 row))))))
    (solve (place-initial-row) 1)))

(define NQUEEN-N
  (let ([env-val (getenv "SEED_NQUEEN")])
    (if env-val (string->number env-val) 14)))

(define (run-benchmark)
  (time
    (begin
      (display (length (n-queens NQUEEN-N)))
      (display " solutions")
      (newline))))
)

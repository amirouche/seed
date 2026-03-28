#!/usr/bin/env scheme --script
;;; Collatz benchmark — native Chez Scheme

(optimize-level 2)
(collect-request-handler void)

(define-syntax and2 (syntax-rules () [(_ a b) (if a b #f)]))
(define-syntax or2  (syntax-rules () [(_ a b) (let ([v a]) (if v v b))]))

(define (collatz-length n)
  (let count ([x n] [steps 0])
    (if (= x 1) steps
        (if (even? x)
            (count (quotient x 2) (+ steps 1))
            (count (+ (* 3 x) 1) (+ steps 1))))))

(define (find-longest-collatz limit)
  (let search ([i 1] [best-n 1] [best-len 0])
    (if (>= i limit) (list best-n best-len)
        (let ([len (collatz-length i)])
          (if (> len best-len)
              (search (+ i 1) i len)
              (search (+ i 1) best-n best-len))))))

(define (count-special limit)
  (let loop ([i 1] [count 0])
    (if (>= i limit) count
        (let ([div3 (= (remainder i 3) 0)]
              [div7 (= (remainder i 7) 0)])
          (if (or2 (and2 div3 div7)
                   (and2 (not div3) (not div7)))
              (loop (+ i 1) (+ count 1))
              (loop (+ i 1) count))))))

(define collatz-limit
  (let ([env-val (getenv "SEED_COLLATZ")])
    (if env-val (string->number env-val) 20000000)))
(define special-limit
  (let ([env-val (getenv "SEED_SPECIAL")])
    (if env-val (string->number env-val) 40000000)))

(time
  (begin
    (display "Collatz: ") (display (find-longest-collatz collatz-limit)) (newline)
    (display "Special: ") (display (count-special special-limit)) (newline)))

(library (benchmarks abacus abacus)
  (export run-benchmark)
  (import (chezscheme)
          (only (match) match guard))

(define eval-expr
  (lambda (expr)
    (match expr
      [(+ ,[a] ,[b])            (+ a b)]
      [(- ,[a] ,[b])            (- a b)]
      [(* ,[a] ,[b])            (* a b)]
      [(/ ,[a] ,[b])            (quotient a b)]
      [,n (guard (number? n))   n])))

(define make-sum-tree
  (lambda (n)
    (let build ([i 1])
      (if (= i n) n (list '+ i (build (+ i 1)))))))

(define make-balanced-tree
  (lambda (d)
    (if (= d 0)
        1
        (list '+ (make-balanced-tree (- d 1))
                  (make-balanced-tree (- d 1))))))

(define ABACUS-DEPTH
  (let ([env-val (getenv "SEED_ABACUS_DEPTH")])
    (if env-val (string->number env-val) 29)))

(define (run-benchmark)
  (display "Arithmetic Evaluator Benchmark (SRFI-241 match catamorphism)")
  (newline)
  (newline)

  ;; --- Correctness tests ---
  (display "Simple:  (+ 1 2) = ")
  (display (eval-expr '(+ 1 2)))
  (newline)

  (display "Nested:  (* (+ 3 4) (- 10 2)) = ")
  (display (eval-expr '(* (+ 3 4) (- 10 2))))
  (newline)

  (display "Division: (/ (* 100 (+ 2 3)) (- 20 10)) = ")
  (display (eval-expr '(/ (* 100 (+ 2 3)) (- 20 10))))
  (newline)

  ;; --- Deep right-leaning: sum 1..100 ---
  (let* ([sum100 (make-sum-tree 100)]
         [result (eval-expr sum100)])
    (display "Sum 1..100 (depth 99): ")
    (display result)
    (newline))

  ;; --- Balanced trees ---
  (let* ([bal10 (make-balanced-tree 10)]
         [result (eval-expr bal10)])
    (display "Balanced tree depth 10 (1024 leaves): ")
    (display result)
    (newline))

  (let ([tree (time (make-balanced-tree ABACUS-DEPTH))])
    (display "Balanced tree depth ")
    (display ABACUS-DEPTH)
    (display ": ")
    (let ([result (time (eval-expr tree))])
      (display result)
      (newline))))
)

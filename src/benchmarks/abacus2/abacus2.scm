(library (benchmarks abacus2 abacus2)
  (export run-benchmark)
  (import (chezscheme)
          (only (match) match guard))

;; Multi-operand evaluator using ellipsis + catamorphism
;; The ,[args] ... pattern recursively evaluates each argument
;; and collects them into a list, which we then apply the operation to.
(define eval-expr
  (lambda (expr)
    (match expr
      [(+ ,[args] ...)          (apply + args)]
      [(- ,[args] ...)          (apply - args)]
      [(* ,[args] ...)          (apply * args)]
      [(/ ,[args] ...)          (apply quotient args)]
      [,n (guard (number? n))   n])))

;; Build flat sum: (+ 1 2 3 ... n)
(define make-sum-tree
  (lambda (n)
    (cons '+ (reverse
              (let build ([i 1] [acc '()])
                (if (> i n)
                    acc
                    (build (+ i 1) (cons i acc))))))))

;; Build balanced ternary (3-ary) tree of depth d
(define make-balanced-tree
  (lambda (d)
    (if (= d 0)
        1
        (list '+ (make-balanced-tree (- d 1))
                  (make-balanced-tree (- d 1))
                  (make-balanced-tree (- d 1))))))

;; Build a mixed tree with varying operand counts (3-5 operands per node)
(define make-mixed-tree
  (lambda (d)
    (letrec ([make-node
              (lambda (depth variant)
                (if (= depth 0)
                    1
                    (let ([count (+ 3 (modulo variant 3))])  ;; 3, 4, or 5 children
                      (cons '+ (make-children (- depth 1) variant count)))))]
             [make-children
              (lambda (depth variant count)
                (if (= count 0)
                    '()
                    (cons (make-node depth (+ variant count))
                          (make-children depth (+ variant 1) (- count 1)))))])
      (make-node d 0))))

(define ABACUS-DEPTH
  (let ([env-val (getenv "SEED_ABACUS2_DEPTH")])
    (if env-val (string->number env-val) 18)))

(define (run-benchmark)
  (display "Multi-operand Arithmetic Evaluator Benchmark (SRFI-241 match catamorphism)")
  (newline)
  (newline)

  ;; --- Correctness tests ---
  (display "Simple 3-arg:  (+ 1 2 3) = ")
  (display (eval-expr '(+ 1 2 3)))
  (newline)

  (display "Simple 4-arg:  (* 2 3 4 5) = ")
  (display (eval-expr '(* 2 3 4 5)))
  (newline)

  (display "Nested:  (* (+ 3 4 5) (- 10 2)) = ")
  (display (eval-expr '(* (+ 3 4 5) (- 10 2))))
  (newline)

  (display "Division: (/ (* 100 2 3) (- 20 10)) = ")
  (display (eval-expr '(/ (* 100 2 3) (- 20 10))))
  (newline)

  ;; --- Multi-operand sum: 1..50 ---
  (let* ([sum50 (make-sum-tree 50)]
         [result (eval-expr sum50)])
    (display "Sum 1..50 (multi-operand): ")
    (display result)
    (newline))

  ;; --- Balanced ternary tree ---
  (let* ([bal8 (make-balanced-tree 8)]
         [result (eval-expr bal8)])
    (display "Balanced ternary tree depth 8 (6561 leaves): ")
    (display result)
    (newline))

  ;; --- Mixed tree with varying operand counts ---
  (let* ([mixed6 (make-mixed-tree 6)]
         [result (eval-expr mixed6)])
    (display "Mixed tree depth 6 (3-5 operands per node): ")
    (display result)
    (newline))

  ;; --- Main benchmark: configurable depth ternary tree ---
  (let ([tree (time (make-balanced-tree ABACUS-DEPTH))])
    (display "Balanced ternary tree depth ")
    (display ABACUS-DEPTH)
    (display ": ")
    (let ([result (time (eval-expr tree))])
      (display result)
      (newline))))
)

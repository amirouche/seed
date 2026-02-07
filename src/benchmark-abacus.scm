;;; benchmark-abacus.scm — Arithmetic Evaluator Benchmark (Chez Scheme)
;;;
;;; Native Chez Scheme version using SRFI-241 pattern matching.
;;; Exercises match catamorphism (,[x]) to implement a recursive
;;; arithmetic expression evaluator via pattern-directed descent.
;;;
;;; Run: scheme --script benchmark-abacus.scm

(import (chezscheme))
(optimize-level 3)
(collect-request-handler void)
(library-directories (cons "srfi-241/lib" (library-directories)))
(import (only (srfi :241) match guard))

;; ============================================================
;; TIMING HELPERS
;; ============================================================

(define (elapsed-seconds start end)
  (let ([d (time-difference end start)])
    (+ (time-second d) (/ (time-nanosecond d) 1e9))))
(define __bench-t0 (current-time 'time-monotonic))

(define (current-nanoseconds)
  (let ([t (current-time 'time-monotonic)])
    (+ (* (time-second t) 1000000000)
       (time-nanosecond t))))

;; ============================================================
;; ARITHMETIC EVALUATOR (catamorphism-based)
;; ============================================================
;; ,[a] recursively evaluates sub-expressions via match's loop.
;; The entire recursive descent is driven by the pattern matcher.

(define eval-expr
  (lambda (expr)
    (match expr
      [(+ ,[a] ,[b])            (+ a b)]
      [(- ,[a] ,[b])            (- a b)]
      [(* ,[a] ,[b])            (* a b)]
      [(/ ,[a] ,[b])            (quotient a b)]
      [,n (guard (number? n))   n])))

;; ============================================================
;; TREE GENERATORS
;; ============================================================

;; Build right-leaning (+ 1 (+ 2 (+ 3 ... (+ (n-1) n)...)))
(define make-sum-tree
  (lambda (n)
    (let build ([i 1])
      (if (= i n) n (list '+ i (build (+ i 1)))))))

;; Build balanced binary tree of depth d
;; Each leaf is 1, internal nodes are (+).
;; Result: 2^d leaves, each = 1, so total = 2^d.
(define make-balanced-tree
  (lambda (d)
    (if (= d 0)
        1
        (list '+ (make-balanced-tree (- d 1))
                  (make-balanced-tree (- d 1))))))


;; ============================================================
;; BENCHMARK
;; ============================================================

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

(let ([sum100 (make-sum-tree 100)])
  (let ([t0 (current-nanoseconds)])
    (let ([result (eval-expr sum100)])
      (let ([t1 (current-nanoseconds)])
        (display "Sum 1..100 (depth 99): ")
        (display result)
        (display " (eval: ")
        (display (quotient (- t1 t0) 1000000))
        (display "ms)")
        (newline)))))

;; --- Balanced trees ---

(let ([bal10 (make-balanced-tree 10)])
  (let ([t0 (current-nanoseconds)])
    (let ([result (eval-expr bal10)])
      (let ([t1 (current-nanoseconds)])
        (display "Balanced tree depth 10 (1024 leaves): ")
        (display result)
        (display " (eval: ")
        (display (quotient (- t1 t0) 1000000))
        (display "ms)")
        (newline)))))

(let ([t0 (current-time 'time-monotonic)])
  (let ([tree (make-balanced-tree 27)])
    (let ([t1 (current-time 'time-monotonic)])
      (let ([result (eval-expr tree)])
        (let ([t2 (current-time 'time-monotonic)])
          (display "Balanced tree depth 27: ")
          (display result)
          (fprintf (current-output-port)
                   " (tree: ~,3fs, eval: ~,3fs)~n"
                   (elapsed-seconds t0 t1)
                   (elapsed-seconds t1 t2))
          (fprintf (current-error-port) "~nTREE-BUILD: ~,6fs~n"
                   (elapsed-seconds t0 t1))
          (fprintf (current-error-port) "EVAL-EXPR: ~,6fs~n"
                   (elapsed-seconds t1 t2)))))))

(let ([__bench-t1 (current-time 'time-monotonic)])
  (fprintf (current-error-port) "MONOTONIC: ~,6fs~n"
           (elapsed-seconds __bench-t0 __bench-t1)))

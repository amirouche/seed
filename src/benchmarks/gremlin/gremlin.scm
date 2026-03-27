(library (benchmarks gremlin gremlin)
  (export run-benchmark)
  (import (chezscheme))

;; ============================================================
;; gremlin-fold — syntax-rules macro
;; ============================================================
;;
;; (gremlin-fold name stream acc body)
;;   Expands to fold-left that binds each element to name.
;;
;; Compare with the Seed2 vau version:
;;   Seed2: 5-line vau operative (runtime code, compiler-specialized)
;;   Chez:  4-line syntax-rules macro (compile-time pattern rewrite)

;; Note: syntax-rules hygiene prevents the macro from introducing
;; 'acc' — the user's body can't reference a macro-introduced binding.
;; So we require the user to name the accumulator explicitly.
;; This is a fundamental difference from Seed2's vau, which shares
;; the caller's scope and doesn't have hygiene barriers.
(define-syntax gremlin-fold
  (syntax-rules ()
    [(_ name stream-expr acc acc-expr body)
     (fold-left
       (lambda (acc name) body)
       acc-expr
       stream-expr)]))

;; ============================================================
;; Deterministic PRNG
;; ============================================================

(define (rng-next s)
  (let ([next (remainder (+ (* s 1103515245) 12345) 2147483648)])
    (if (< next 0) (- 0 next) next)))

;; ============================================================
;; Graph representation (list-based, same as Seed2 version)
;; ============================================================

(define (make-graph n edges-per-vertex num-groups rng-seed)
  (let build ([i 0] [s rng-seed] [acc '()])
    (if (= i n)
        (let ([entries (reverse acc)])
          (let add-edges ([rest entries] [idx 0] [s2 s] [result '()])
            (if (null? rest)
                (reverse result)
                (let ([entry (car rest)])
                  (let add-e ([j 0] [s3 s2] [nbrs '()])
                    (if (= j edges-per-vertex)
                        (add-edges (cdr rest) (+ idx 1) s3
                                   (cons (cons (car entry) nbrs) result))
                        (let* ([s4 (rng-next s3)]
                               [target (remainder s4 n)])
                          (if (= target idx)
                              (add-e j s4 nbrs)
                              (add-e (+ j 1) s4 (cons target nbrs))))))))))
        (let ([s2 (rng-next s)])
          (build (+ i 1) s2
                 (cons (list (remainder s2 num-groups)) acc))))))

(define (graph-ref g v) (list-ref g v))
(define (graph-group entry) (car entry))
(define (graph-neighbors entry) (cdr entry))

(define (out g v) (graph-neighbors (graph-ref g v)))

(define (same-group? g a b)
  (= (graph-group (graph-ref g a))
     (graph-group (graph-ref g b))))

(define (edge? g from to)
  (if (memv to (graph-neighbors (graph-ref g from))) #t #f))

;; ============================================================
;; Triangle counting — same nested gremlin-fold syntax as Seed2
;; ============================================================

(define (count-triangles g)
  (gremlin-fold a (iota (length g)) acc 0
    (gremlin-fold b (out g a) acc acc
      (if (not (same-group? g a b)) acc
          (gremlin-fold c (out g b) acc acc
            (if (not (same-group? g a c)) acc
                (if (edge? g c a)
                    (+ acc 1)
                    acc)))))))

;; ============================================================
;; Benchmark
;; ============================================================

(define GREMLIN-N
  (let ([env-val (getenv "SEED_GREMLIN_N")])
    (if env-val (string->number env-val) 20000)))

(define GREMLIN-E
  (let ([env-val (getenv "SEED_GREMLIN_E")])
    (if env-val (string->number env-val) 20)))

(define (run-benchmark)
  (display "Gremlin Graph Traversal Benchmark (gremlin-fold with syntax-rules)")
  (newline)
  (newline)

  ;; Correctness check
  (let ([g (make-graph 20 5 3 42)])
    (let ([tri (count-triangles g)])
      (display "Small graph (20 vertices, 5 edges/v, 3 groups): ")
      (display tri)
      (display " triangles")
      (newline)))

  ;; Main benchmark
  (let ([g (make-graph GREMLIN-N GREMLIN-E 10 12345)])
    (display "Graph: ")
    (display GREMLIN-N)
    (display " vertices, ")
    (display GREMLIN-E)
    (display " edges/vertex, 10 groups")
    (newline)
    (let ([tri (time (count-triangles g))])
      (display tri)
      (display " triangles")
      (newline))))
)

(library (benchmarks gremlin gremlin)
  (export run-benchmark)
  (import (chezscheme))

;; ============================================================
;; Deterministic PRNG (linear congruential, purely functional)
;; ============================================================

(define (rng-next s)
  (let ([next (remainder (+ (* s 1103515245) 12345) 2147483648)])
    (if (< next 0) (- 0 next) next)))

;; ============================================================
;; Graph representation (list-based, same as Seed2 version)
;; ============================================================
;; Graph is a list of entries ordered by vertex id: ((group . neighbors) ...)
;; Vertex i is at position i (accessed via list-ref).

(define (make-graph n edges-per-vertex num-groups rng-seed)
  ;; Build vertex entries with groups (no edges yet)
  (let build ([i 0] [s rng-seed] [acc '()])
    (if (= i n)
        (let ([entries (reverse acc)])
          ;; Add random edges
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

(define (edge? g from to)
  (memv to (graph-neighbors (graph-ref g from))))

;; ============================================================
;; Triangle counting — plain let bindings (native Chez)
;; ============================================================

(define (count-triangles g n)
  (let loop-a ([ai 0] [count 0])
    (if (= ai n) count
        (let* ([a-entry (graph-ref g ai)]
               [a-grp (graph-group a-entry)]
               [a-nbrs (graph-neighbors a-entry)])
          (let loop-b ([bs a-nbrs] [count count])
            (if (null? bs)
                (loop-a (+ ai 1) count)
                (let* ([bi (car bs)]
                       [b-entry (graph-ref g bi)]
                       [b-grp (graph-group b-entry)])
                  (if (not (= a-grp b-grp))
                      (loop-b (cdr bs) count)
                      (let ([b-nbrs (graph-neighbors b-entry)])
                        (let loop-c ([cs b-nbrs] [count count])
                          (if (null? cs)
                              (loop-b (cdr bs) count)
                              (let ([ci (car cs)])
                                (if (and (= a-grp (graph-group (graph-ref g ci)))
                                         (edge? g ci ai))
                                    (loop-c (cdr cs) (+ count 1))
                                    (loop-c (cdr cs) count))))))))))))))

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
  (display "Gremlin Graph Traversal Benchmark")
  (newline)
  (newline)

  ;; Correctness check
  (let ([g (make-graph 20 5 3 42)])
    (let ([tri (count-triangles g 20)])
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
    (let ([tri (time (count-triangles g GREMLIN-N))])
      (display tri)
      (display " triangles")
      (newline))))
)

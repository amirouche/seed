(library (benchmarks gremlin gremlin-pipeline)
  (export run-benchmark)
  (import (chezscheme))

;; ============================================================
;; traverse — syntax-case macro, TinkerPop-style pipeline DSL
;; ============================================================
;;
;; Chez translation of the Seed2 pipeline benchmark.
;; syntax-case recursively walks the flat step list at compile time,
;; producing nested loops — same code shape as the Seed2 vau version.
;;
;; Compare with Seed2:
;;   Seed2: vau operative + specializer unfolds recursive calls
;;   Chez:  syntax-case macro + pattern matching unfolds step list
;;
;; Steps:
;;   (V)          — source: all vertices           [g.V()]
;;   (as name)    — label current traverser        [.as('name')]
;;   (out)        — flat-map outgoing edges        [.out()]
;;   (where pred) — filter by predicate            [.filter{pred}]
;;   (count)      — terminal: count traversers     [.count()]

;; traverse introduces g and acc in the caller's scope via datum->syntax,
;; then delegates to traverse-steps which recursively processes the steps.
;; k carries the call-site context for hygiene-breaking.

(define-syntax traverse
  (lambda (x)
    (syntax-case x ()
      [(k graph-expr step ...)
       (with-syntax ([acc (datum->syntax #'k 'acc)]
                     [g   (datum->syntax #'k 'g)])
         #'(let ([g graph-expr] [acc 0])
             (traverse-steps k g #f step ...)))])))

(define-syntax traverse-steps
  (lambda (x)
    (syntax-case x (V as out where count)
      ;; No more steps → increment acc
      [(_ k g last-as)
       (with-syntax ([acc (datum->syntax #'k 'acc)])
         #'(+ acc 1))]
      ;; (V) → set stream to all vertices
      [(_ k g last-as (V) rest ...)
       #'(traverse-steps k g last-as rest ...)]
      ;; (as name) → loop over stream, bind each to name
      [(_ k g last-as (as name) rest ...)
       (with-syntax ([acc (datum->syntax #'k 'acc)])
         #'(let loop ([items (iota (length g))] [acc acc])
             (if (null? items) acc
                 (let ([name (car items)])
                   (loop (cdr items)
                         (traverse-steps k g name rest ...))))))]
      ;; (out) followed by (as name) → loop over out-neighbors
      [(_ k g last-as (out) (as name) rest ...)
       (with-syntax ([acc (datum->syntax #'k 'acc)])
         #'(let loop ([items (out g last-as)] [acc acc])
             (if (null? items) acc
                 (let ([name (car items)])
                   (loop (cdr items)
                         (traverse-steps k g name rest ...))))))]
      ;; (where pred) → guard
      [(_ k g last-as (where pred) rest ...)
       (with-syntax ([acc (datum->syntax #'k 'acc)])
         #'(if (not pred) acc
               (traverse-steps k g last-as rest ...)))]
      ;; (count) → terminal
      [(_ k g last-as (count))
       (with-syntax ([acc (datum->syntax #'k 'acc)])
         #'(+ acc 1))])))

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
;; Triangle counting — flat pipeline, same syntax as Seed2
;; ============================================================

(define (count-triangles g)
  (traverse g
    (V)
    (as a)
    (out)
    (as b)
    (where (same-group? g a b))
    (out)
    (as c)
    (where (same-group? g a c))
    (where (edge? g c a))
    (count)))

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
  (display "Gremlin Pipeline Benchmark (TinkerPop-style traversal, syntax-case)")
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

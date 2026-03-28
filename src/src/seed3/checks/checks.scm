;;;
;;; Seed3 Unit Test Suite — ported from checks.scm
;;;
;;; Run: cd <repo-root> && scheme --script src/seed3/checks/checks.scm
;;;

(import (seed3))

;; =========================================================================
;; Test Infrastructure
;; =========================================================================

(configure-development-mode #t)

(define test-count 0)
(define test-pass 0)
(define test-fail 0)

(define (test name input expected)
  (set! test-count (+ test-count 1))
  (let ([result (parse input)])
    (if (equal? result expected)
        (begin
          (set! test-pass (+ test-pass 1))
          (printf "  PASS ~a~n" name))
        (begin
          (set! test-fail (+ test-fail 1))
          (printf "  FAIL ~a~n    expected: ~s~n    got:      ~s~n"
                  name expected result)))))

(define (test-roundtrip name input)
  (set! test-count (+ test-count 1))
  (let ([result (ast-to-source (parse input))])
    (if (equal? result input)
        (begin
          (set! test-pass (+ test-pass 1))
          (printf "  PASS ~a (roundtrip)~n" name))
        (begin
          (set! test-fail (+ test-fail 1))
          (printf "  FAIL ~a (roundtrip)~n    input:  ~s~n    result: ~s~n"
                  name input result)))))

;; =========================================================================
;; Step 1 Tests: Parse
;; =========================================================================

(printf "~n=== Seed3 Step 1: Parse ===~n~n")

;; --- Constants ---
(printf "── Constants ──~n")
(test "number"     42       '(const 42))
(test "negative"   -3       '(const -3))
(test "boolean/t"  #t       '(const #t))
(test "boolean/f"  #f       '(const #f))
(test "string"     "hello"  '(const "hello"))
(test "null"       '()      '(const ()))

;; --- Variables ---
(printf "── Variables ──~n")
(test "var/simple" 'x '(var x))
(test "var/long"   'my-var '(var my-var))

;; --- Quote ---
(printf "── Quote ──~n")
(test "quote/symbol" '(quote foo)      '(quot foo))
(test "quote/list"   '(quote (a b c))  '(quot (a b c)))
(test "quote/nested" '(quote (a (b) c)) '(quot (a (b) c)))
(test "quote/number" '(quote 42)       '(quot 42))

;; --- Conditionals ---
(printf "── Conditionals ──~n")
(test "if/3arm" '(if x y z)
  '(if (var x) (var y) (var z)))
(test "if/2arm" '(if x y)
  '(if (var x) (var y) (const #f)))
(test "if/nested" '(if (< 1 2) 10 20)
  '(if (call (var <) ((const 1) (const 2))) (const 10) (const 20)))

;; --- Begin ---
(printf "── Begin ──~n")
(test "begin/single" '(begin 42)
  '(begin (const 42)))
(test "begin/multi" '(begin 1 2 3)
  '(begin (const 1) (const 2) (const 3)))

;; --- Let ---
(printf "── Let ──~n")
(test "let/simple" '(let ((x 5)) x)
  '(let ((x (const 5))) (var x)))
(test "let/multi-binding" '(let ((x 1) (y 2)) (+ x y))
  '(let ((x (const 1)) (y (const 2)))
     (call (var +) ((var x) (var y)))))
(test "let/multi-body" '(let ((x 1)) x (+ x 1))
  '(let ((x (const 1)))
     (begin (var x) (call (var +) ((var x) (const 1))))))

;; --- Let* ---
(printf "── Let* ──~n")
(test "let*/empty" '(let* () 42)
  '(const 42))
(test "let*/single" '(let* ((x 5)) x)
  '(let ((x (const 5))) (var x)))
(test "let*/nested" '(let* ((x 1) (y x)) y)
  '(let ((x (const 1))) (let ((y (var x))) (var y))))
(test "let*/multi-body" '(let* () 1 2)
  '(begin (const 1) (const 2)))

;; --- Letrec ---
(printf "── Letrec ──~n")
(test "letrec/simple" '(letrec ((f (lambda (x) x))) (f 1))
  '(letrec ((f (wrap (vau (x) #f (var x)))))
     (call (var f) ((const 1)))))
(test "letrec/multi-body" '(letrec ((x 1)) x (+ x 1))
  '(letrec ((x (const 1)))
     (begin (var x) (call (var +) ((var x) (const 1))))))

;; --- Lambda -> wrap(vau) ---
(printf "── Lambda -> wrap(vau) ──~n")
(test "lambda/basic" '(lambda (x) (+ x 1))
  '(wrap (vau (x) #f (call (var +) ((var x) (const 1))))))
(test "lambda/multi-param" '(lambda (a b) a)
  '(wrap (vau (a b) #f (var a))))
(test "lambda/rest-param" '(lambda args args)
  '(wrap (vau args #f (var args))))
(test "lambda/dotted-param" '(lambda (a . b) b)
  '(wrap (vau (a . b) #f (var b))))
(test "lambda/nullary" '(lambda () 42)
  '(wrap (vau () #f (const 42))))
(test "lambda/multi-body" '(lambda (x) 1 2 3)
  '(wrap (vau (x) #f (begin (const 1) (const 2) (const 3)))))
(test "lambda/nested" '(lambda (x) (lambda (y) (+ x y)))
  '(wrap (vau (x) #f
    (wrap (vau (y) #f
      (call (var +) ((var x) (var y))))))))

;; --- Vau ---
(printf "── Vau ──~n")
(test "vau/basic" '(vau (x) e x)
  '(vau (x) e (var x)))
(test "vau/ignore-underscore" '(vau (x) _ x)
  '(vau (x) #f (var x)))
(test "vau/ignore-percent" '(vau (x) %ignore x)
  '(vau (x) #f (var x)))
(test "vau/with-eval" '(vau (x) e (eval x e))
  '(vau (x) e (eval (var x) (var e))))
(test "vau/multi-body" '(vau (x y) e x y)
  '(vau (x y) e (begin (var x) (var y))))
(test "vau/rest-param" '(vau args _ args)
  '(vau args #f (var args)))

;; --- Eval ---
(printf "── Eval ──~n")
(test "eval/simple" '(eval x e)
  '(eval (var x) (var e)))
(test "eval/nested" '(eval (+ 1 2) e)
  '(eval (call (var +) ((const 1) (const 2))) (var e)))

;; --- Application ---
(printf "── Application ──~n")
(test "app/primitive" '(+ 1 2)
  '(call (var +) ((const 1) (const 2))))
(test "app/lambda-call" '((lambda (x) x) 5)
  '(call (wrap (vau (x) #f (var x))) ((const 5))))
(test "app/nullary" '(f)
  '(call (var f) ()))
(test "app/nested" '(f (g x))
  '(call (var f) ((call (var g) ((var x))))))

;; --- Combined ---
(printf "── Combined ──~n")
(test "factorial"
  '(letrec ((fact (lambda (n)
                    (if (= n 0) 1 (* n (fact (- n 1)))))))
     (fact 5))
  '(letrec ((fact (wrap (vau (n) #f
                    (if (call (var =) ((var n) (const 0)))
                        (const 1)
                        (call (var *) ((var n)
                          (call (var fact) ((call (var -) ((var n) (const 1))))))))))))
     (call (var fact) ((const 5)))))

(test "vau-as-macro"
  '(letrec ((when (vau (test expr) e
                    (if (eval test e) (eval expr e) #f))))
     (when #t 42))
  '(letrec ((when (vau (test expr) e
                    (if (eval (var test) (var e))
                        (eval (var expr) (var e))
                        (const #f)))))
     (call (var when) ((const #t) (const 42)))))

(test "vau-quote-like"
  '((vau (x) _ x) (+ 1 2))
  '(call (vau (x) #f (var x)) ((call (var +) ((const 1) (const 2))))))

(test "higher-order"
  '(map (lambda (x) (+ x 1)) (list 1 2 3))
  '(call (var map)
     ((wrap (vau (x) #f (call (var +) ((var x) (const 1)))))
      (call (var list) ((const 1) (const 2) (const 3))))))

(test "closure"
  '(let ((x 10))
     (let ((f (lambda (y) (+ x y))))
       (f 5)))
  '(let ((x (const 10)))
     (let ((f (wrap (vau (y) #f (call (var +) ((var x) (var y)))))))
       (call (var f) ((const 5))))))

;; --- Roundtrip: parse -> ast-to-source ---
(printf "── Roundtrip (parse -> ast-to-source) ──~n")
(test-roundtrip "rt/number" 42)
(test-roundtrip "rt/var" 'x)
(test-roundtrip "rt/quote" '(quote (a b)))
(test-roundtrip "rt/if" '(if x y z))
(test-roundtrip "rt/begin" '(begin 1 2 3))
(test-roundtrip "rt/let" '(let ((x 5)) x))
(test-roundtrip "rt/lambda" '(lambda (x) (+ x 1)))
(test-roundtrip "rt/app" '(f 1 2))
(test-roundtrip "rt/nested-lambda" '(lambda (x) (lambda (y) (+ x y))))
(test-roundtrip "rt/letrec" '(letrec ((f (lambda (x) x))) (f 1)))

;; --- Step 1 Summary ---
(printf "~n── Step 1 Summary ──~n")
(printf "  ~a/~a passed" test-pass test-count)
(if (> test-fail 0)
    (printf ", ~a FAILED~n" test-fail)
    (printf "~n"))
(when (> test-fail 0) (exit 1))

;; =========================================================================
;; Step 2 Tests: Annotate
;; =========================================================================

(printf "~n=== Seed3 Step 2: Annotate ===~n~n")

(define (test-annotate name input expected)
  (set! test-count (+ test-count 1))
  (let ([result ((annotate '()) (parse input))])
    (if (equal? result expected)
        (begin
          (set! test-pass (+ test-pass 1))
          (printf "  PASS ~a~n" name))
        (begin
          (set! test-fail (+ test-fail 1))
          (printf "  FAIL ~a~n    expected: ~s~n    got:      ~s~n"
                  name expected result)))))

;; --- Constants & Leaves ---
(printf "── Leaves ──~n")
(test-annotate "const" 42 '(const 42))
(test-annotate "quot" '(quote foo) '(quot foo))
(test-annotate "free-var" 'x '(var x free))

;; --- Lambda bodies ---
(printf "── Lambda bodies ──~n")
(test-annotate "lambda/param-local" '(lambda (x) x)
  '(wrap (vau (x) #f (var x local))))
(test-annotate "lambda/free-ref" '(lambda (x) y)
  '(wrap (vau (x) #f (var y free))))
(test-annotate "lambda/mixed" '(lambda (x) (+ x y))
  '(wrap (vau (x) #f
    (call (var + free) ((var x local) (var y free))))))
(test-annotate "lambda/multi-param" '(lambda (a b) (+ a b))
  '(wrap (vau (a b) #f
    (call (var + free) ((var a local) (var b local))))))
(test-annotate "lambda/rest-param" '(lambda args args)
  '(wrap (vau args #f (var args local))))
(test-annotate "lambda/dotted-param" '(lambda (a . b) b)
  '(wrap (vau (a . b) #f (var b local))))

;; --- Vau with live ep ---
(printf "── Vau with ep ──~n")
(test-annotate "vau/ep-local" '(vau (x) e (eval x e))
  '(vau (x) e (eval (var x local) (var e local))))
(test-annotate "vau/ep-and-param" '(vau (test then) e
                                     (if (eval test e) (eval then e) #f))
  '(vau (test then) e
     (if (eval (var test local) (var e local))
         (eval (var then local) (var e local))
         (const #f))))

;; --- Let ---
(printf "── Let ──~n")
(test-annotate "let/binding-local" '(let ((x 5)) x)
  '(let ((x (const 5))) (var x local)))
(test-annotate "let/rhs-in-outer-scope" '(let ((x 5)) (let ((y x)) y))
  '(let ((x (const 5)))
     (let ((y (var x local)))
       (var y local))))
(test-annotate "let/free-in-rhs" '(let ((x z)) x)
  '(let ((x (var z free))) (var x local)))

;; --- Letrec ---
(printf "── Letrec ──~n")
(test-annotate "letrec/self-ref" '(letrec ((f (lambda (x) (f x)))) (f 1))
  '(letrec ((f (wrap (vau (x) #f (call (var f local) ((var x local)))))))
     (call (var f local) ((const 1)))))
(test-annotate "letrec/mutual-ref" '(letrec ((a (lambda () (b)))
                                              (b (lambda () (a))))
                                       (a))
  '(letrec ((a (wrap (vau () #f (call (var b local) ()))))
            (b (wrap (vau () #f (call (var a local) ())))))
     (call (var a local) ())))

;; --- Nested scopes ---
(printf "── Nested scopes ──~n")
(test-annotate "nested/closure" '(let ((x 10)) (lambda (y) (+ x y)))
  '(let ((x (const 10)))
     (wrap (vau (y) #f
       (call (var + free) ((var x local) (var y local)))))))
(test-annotate "nested/shadow" '(let ((x 1)) (let ((x 2)) x))
  '(let ((x (const 1)))
     (let ((x (const 2)))
       (var x local))))

;; --- Full programs ---
(printf "── Full programs ──~n")
(test-annotate "fibonacci"
  '(letrec ((fib (lambda (n)
                   (if (<= n 1) n
                       (+ (fib (- n 1)) (fib (- n 2)))))))
     (fib 10))
  '(letrec ((fib (wrap (vau (n) #f
      (if (call (var <= free) ((var n local) (const 1)))
          (var n local)
          (call (var + free)
            ((call (var fib local) ((call (var - free) ((var n local) (const 1)))))
             (call (var fib local) ((call (var - free) ((var n local) (const 2))))))))))))
     (call (var fib local) ((const 10)))))

(test-annotate "anaphoric-if"
  '(letrec ((aif (vau (test then else) e
                   (let ((it (eval test e)))
                     (if it (eval then e) (eval else e))))))
     (aif (+ 1 2) it 0))
  '(letrec ((aif (vau (test then else) e
      (let ((it (eval (var test local) (var e local))))
        (if (var it local)
            (eval (var then local) (var e local))
            (eval (var else local) (var e local)))))))
     (call (var aif local)
       ((call (var + free) ((const 1) (const 2)))
        (var it free)
        (const 0)))))

;; --- Step 2 Summary ---
(printf "~n── Step 2 Summary ──~n")
(printf "  ~a/~a passed" test-pass test-count)
(if (> test-fail 0)
    (printf ", ~a FAILED~n" test-fail)
    (printf "~n"))
(when (> test-fail 0) (exit 1))

;; =========================================================================
;; Step 3 Tests: Classify
;; =========================================================================

(printf "~n=== Seed3 Step 3: Classify ===~n~n")

(define (pipeline expr)
  (classify ((annotate '()) (parse expr))))

(define (test-classify name input expected)
  (set! test-count (+ test-count 1))
  (let ([result (pipeline input)])
    (if (equal? result expected)
        (begin
          (set! test-pass (+ test-pass 1))
          (printf "  PASS ~a~n" name))
        (begin
          (set! test-fail (+ test-fail 1))
          (printf "  FAIL ~a~n    expected: ~s~n    got:      ~s~n"
                  name expected result)))))

(define (test-pred name pred input expected)
  (set! test-count (+ test-count 1))
  (let ([result (pred input)])
    (if (equal? result expected)
        (begin
          (set! test-pass (+ test-pass 1))
          (printf "  PASS ~a~n" name))
        (begin
          (set! test-fail (+ test-fail 1))
          (printf "  FAIL ~a~n    expected: ~s~n    got:      ~s~n"
                  name expected result)))))

;; --- Predicate unit tests ---
(printf "── ast-uses-eval? ──~n")
(test-pred "uses-eval/const" ast-uses-eval? '(const 42) #f)
(test-pred "uses-eval/var" ast-uses-eval? '(var x local) #f)
(test-pred "uses-eval/call" ast-uses-eval?
  '(call (var + free) ((var x local) (const 1))) #f)
(test-pred "uses-eval/eval" ast-uses-eval?
  '(eval (var x local) (var e local)) #t)
(test-pred "uses-eval/nested-if" ast-uses-eval?
  '(if (var x local) (eval (var y local) (var e local)) (const 1)) #t)
(test-pred "uses-eval/deep-no" ast-uses-eval?
  '(let ((x (const 5))) (call (var + free) ((var x local) (const 1)))) #f)

;; Note: seed3 has no *primitives* — ALL free vars are "free"
(printf "── ast-has-free-variables? ──~n")
(test-pred "has-free/any-free" ast-has-free-variables? '(var + free) #t)
(test-pred "has-free/non-prim" ast-has-free-variables? '(var foo free) #t)
(test-pred "has-free/local" ast-has-free-variables? '(var x local) #f)
(test-pred "has-free/const" ast-has-free-variables? '(const 42) #f)
(test-pred "has-free/free-call" ast-has-free-variables?
  '(call (var + free) ((var x local) (const 1))) #t)

;; --- Classify tests ---
;; Note: without *primitives*, fibonacci does NOT lower to lam (has free vars <=, +, -)
(printf "── Classify: fibonacci -> stays wrap(vau) (no primitives list) ──~n")
(test-classify "fib->wrap"
  '(letrec ((fib (lambda (n)
                   (if (<= n 1) n
                       (+ (fib (- n 1)) (fib (- n 2)))))))
     (fib 10))
  '(letrec ((fib (wrap (vau (n) #f
      (if (call (var <= free) ((var n local) (const 1)))
          (var n local)
          (call (var + free)
            ((call (var fib local) ((call (var - free) ((var n local) (const 1)))))
             (call (var fib local) ((call (var - free) ((var n local) (const 2))))))))))))
     (call (var fib local) ((const 10)))))

(printf "── Classify: anaphoric if -> stays vau ──~n")
(test-classify "aif->vau"
  '(letrec ((aif (vau (test then else) e
                   (let ((it (eval test e)))
                     (if it (eval then e) (eval else e))))))
     (aif (+ 1 2) it 0))
  '(letrec ((aif (vau (test then else) e
      (let ((it (eval (var test local) (var e local))))
        (if (var it local)
            (eval (var then local) (var e local))
            (eval (var else local) (var e local)))))))
     (call (var aif local)
       ((call (var + free) ((const 1) (const 2)))
        (var it free)
        (const 0)))))

;; Pure lambda with NO free vars → lam
(printf "── Classify: pure lambda -> lam ──~n")
(test-classify "pure->lam"
  '(lambda (x) x)
  '(lam (x) (var x local)))

;; Lambda with free vars → stays wrap(vau)
(printf "── Classify: free var -> stays wrap(vau) ──~n")
(test-classify "free-var->wrap"
  '(lambda (x) (foo x))
  '(wrap (vau (x) #f
     (call (var foo free) ((var x local))))))

;; --- Step 3 Summary ---
(printf "~n── Step 3 Summary ──~n")
(printf "  ~a/~a passed" test-pass test-count)
(if (> test-fail 0)
    (printf ", ~a FAILED~n" test-fail)
    (printf "~n"))
(when (> test-fail 0) (exit 1))

;; =========================================================================
;; Step 4 Tests: BTA (analyze-binding-time)
;; =========================================================================

(printf "~n=== Seed3 Step 4: BTA ===~n~n")

(define (pipeline4 expr)
  (analyze-binding-time (classify ((annotate '()) (parse expr)))))

(define (test-bta name input expected)
  (set! test-count (+ test-count 1))
  (let ([result (pipeline4 input)])
    (if (equal? result expected)
        (begin
          (set! test-pass (+ test-pass 1))
          (printf "  PASS ~a~n" name))
        (begin
          (set! test-fail (+ test-fail 1))
          (printf "  FAIL ~a~n    expected: ~s~n    got:      ~s~n"
                  name expected result)))))

(define (test-bt name params ep body expected)
  (set! test-count (+ test-count 1))
  (let ([result (compute-parameter-binding-times params ep body)])
    (if (equal? result expected)
        (begin
          (set! test-pass (+ test-pass 1))
          (printf "  PASS ~a~n" name))
        (begin
          (set! test-fail (+ test-fail 1))
          (printf "  FAIL ~a~n    expected: ~s~n    got:      ~s~n"
                  name expected result)))))

;; --- compute-parameter-binding-times unit tests ---
(printf "── compute-parameter-binding-times ──~n")

(test-bt "bt/all-eval" '(test then else) 'e
  '(let ((it (eval (var test local) (var e local))))
     (if (var it local)
         (eval (var then local) (var e local))
         (eval (var else local) (var e local))))
  '((test static-eval) (then static-eval) (else static-eval)))

(test-bt "bt/dynamic" '(x) 'e
  '(if (var x local) (eval (var x local) (var e local)) (const 0))
  '((x dynamic)))

(test-bt "bt/syntax-only" '(expr) 'e
  '(call (var list free) ((var expr local)))
  '((expr static-syntax)))

(test-bt "bt/unused-param" '(x y) 'e
  '(eval (var x local) (var e local))
  '((x static-eval) (y static-syntax)))

(test-bt "bt/no-params" '() 'e
  '(const 42)
  '())

;; --- BTA integration tests ---
(printf "── BTA: anaphoric if -> all static-eval ──~n")
(test-bta "aif->bta"
  '(letrec ((aif (vau (test then else) e
                   (let ((it (eval test e)))
                     (if it (eval then e) (eval else e))))))
     (aif (+ 1 2) it 0))
  '(letrec ((aif (vau (test then else) e
      (let ((it (eval (var test local) (var e local))))
        (if (var it local)
            (eval (var then local) (var e local))
            (eval (var else local) (var e local))))
      ((test static-eval) (then static-eval) (else static-eval)))))
     (call (var aif local)
       ((call (var + free) ((const 1) (const 2)))
        (var it free)
        (const 0)))))

;; fibonacci stays wrap(vau) in seed3 (no primitives list)
(printf "── BTA: fibonacci -> wrap(vau) (no annotation) ──~n")
(test-bta "fib->wrap-no-bta"
  '(letrec ((fib (lambda (n)
                   (if (<= n 1) n
                       (+ (fib (- n 1)) (fib (- n 2)))))))
     (fib 10))
  '(letrec ((fib (wrap (vau (n) #f
      (if (call (var <= free) ((var n local) (const 1)))
          (var n local)
          (call (var + free)
            ((call (var fib local) ((call (var - free) ((var n local) (const 1)))))
             (call (var fib local) ((call (var - free) ((var n local) (const 2))))))))))))
     (call (var fib local) ((const 10)))))

(printf "── BTA: mixed use -> dynamic ──~n")
(test-bta "mixed->dynamic"
  '(vau (x) e (if x (eval x e) 0))
  '(vau (x) e
     (if (var x local) (eval (var x local) (var e local)) (const 0))
     ((x dynamic))))

(printf "── BTA: syntax only ──~n")
(test-bta "syntax-only"
  '(vau (expr) e (list expr))
  '(vau (expr) e
     (call (var list free) ((var expr local)))
     ((expr static-syntax))))

(printf "── BTA: unused param ──~n")
(test-bta "unused->syntax"
  '(vau (x y) e (eval x e))
  '(vau (x y) e
     (eval (var x local) (var e local))
     ((x static-eval) (y static-syntax))))

(printf "── BTA: free var -> wrap(vau) (passes through) ──~n")
(test-bta "free-var->wrap"
  '(lambda (x) (foo x))
  '(wrap (vau (x) #f
     (call (var foo free) ((var x local))))))

(printf "── BTA: nested vau ──~n")
(test-bta "nested-vau"
  '(vau (x) e
     (let ((f (vau (y) e2 (eval y e2))))
       (eval x e)))
  '(vau (x) e
     (let ((f (vau (y) e2
                (eval (var y local) (var e2 local))
                ((y static-eval)))))
       (eval (var x local) (var e local)))
     ((x static-eval))))

;; --- Step 4 Summary ---
(printf "~n── Step 4 Summary ──~n")
(printf "  ~a/~a passed" test-pass test-count)
(if (> test-fail 0)
    (printf ", ~a FAILED~n" test-fail)
    (printf "~n"))
(when (> test-fail 0) (exit 1))

;; =========================================================================
;; Step 5 Tests: Codegen + Driver
;; =========================================================================

(printf "~n=== Seed3 Step 5: Codegen + Driver ===~n~n")

;; --- Execution tests ---
(define (test-run name input expected)
  (set! test-count (+ test-count 1))
  (let ([result (run input)])
    (if (equal? result expected)
        (begin
          (set! test-pass (+ test-pass 1))
          (printf "  PASS ~a~n" name))
        (begin
          (set! test-fail (+ test-fail 1))
          (printf "  FAIL ~a~n    expected: ~s~n    got:      ~s~n"
                  name expected result)))))

(define (test-run-env name input expected)
  (set! test-count (+ test-count 1))
  (let ([result (run-with-environment input)])
    (if (equal? result expected)
        (begin
          (set! test-pass (+ test-pass 1))
          (printf "  PASS ~a~n" name))
        (begin
          (set! test-fail (+ test-fail 1))
          (printf "  FAIL ~a~n    expected: ~s~n    got:      ~s~n"
                  name expected result)))))

(printf "── Execution: basic ──~n")
(test-run "run/const" '42 42)
(test-run "run/bool" '#t #t)
(test-run "run/string" '"hello" "hello")
(test-run "run/add" '(+ 1 2) 3)
(test-run "run/nested-arith" '(+ (* 2 3) (- 10 4)) 12)
(test-run "run/if-true" '(if (< 1 2) 10 20) 10)
(test-run "run/if-false" '(if (> 1 2) 10 20) 20)
(test-run "run/quote" '(quote (a b c)) '(a b c))
(test-run "run/null" ''() '())
(test-run "run/cons" '(cons 1 '()) '(1))
(test-run "run/car" '(car '(1 2 3)) 1)
(test-run "run/cdr" '(cdr '(1 2 3)) '(2 3))
(test-run "run/list" '(list 1 2 3) '(1 2 3))
(test-run "run/null?" '(null? '()) #t)
(test-run "run/not" '(not #f) #t)
(test-run "run/abs" '(abs -5) 5)

(printf "── Execution: let/lambda/letrec ──~n")
(test-run "run/let" '(let ((x 5)) (+ x 1)) 6)
(test-run "run/let-multi" '(let ((x 1) (y 2)) (+ x y)) 3)
(test-run "run/lambda-app" '((lambda (x) (+ x 10)) 5) 15)
(test-run "run/closure"
  '(let ((x 10))
     (let ((f (lambda (y) (+ x y))))
       (f 5)))
  15)
(test-run "run/letrec-fact"
  '(letrec ((fact (lambda (n)
                    (if (= n 0) 1 (* n (fact (- n 1)))))))
     (fact 10))
  3628800)
(test-run "run/letrec-mutual"
  '(letrec ((even? (lambda (n) (if (= n 0) #t (odd? (- n 1)))))
            (odd?  (lambda (n) (if (= n 0) #f (even? (- n 1))))))
     (list (even? 10) (odd? 10) (even? 7) (odd? 7)))
  '(#t #f #f #t))

(printf "── Execution: higher-order ──~n")
(test-run "run/map"
  '(map (lambda (x) (+ x 1)) '(1 2 3))
  '(2 3 4))
(test-run "run/apply"
  '(apply + '(1 2 3))
  6)
(test-run "run/length" '(length '(a b c)) 3)
(test-run "run/append" '(append '(1 2) '(3 4)) '(1 2 3 4))

;; --- Vau/eval execution tests (via interpreter) ---
(printf "── Execution: vau/eval (interpreter) ──~n")

(define (test-interp name input expected)
  (set! test-count (+ test-count 1))
  (let ([result (seed-evaluate input environment-ground)])
    (if (equal? result expected)
        (begin
          (set! test-pass (+ test-pass 1))
          (printf "  PASS ~a~n" name))
        (begin
          (set! test-fail (+ test-fail 1))
          (printf "  FAIL ~a~n    expected: ~s~n    got:      ~s~n"
                  name expected result)))))

(test-interp "interp/quote-like"
  '(letrec ((my-quote (vau (x) _ x)))
     (my-quote (+ 1 2)))
  '(+ 1 2))

(test-interp "interp/eval-basic"
  '(letrec ((my-eval (vau (x) e (eval x e))))
     (my-eval (+ 1 2)))
  3)

(test-interp "interp/anaphoric-if"
  '(letrec ((aif (vau (test then else) e
                   (let ((result (eval test e)))
                     (if result
                         (eval (list then result) e)
                         (eval else e))))))
     (aif (+ 1 2) (lambda (it) (* it 10)) 0))
  30)

;; --- transform-top-level tests ---
(printf "── transform-top-level ──~n")

(set! test-count (+ test-count 1))
(let ([result (transform-top-level '((define (f x) (+ x 1)) (f 5)))])
  (if (equal? result '(letrec ((f (lambda (x) (+ x 1)))) (f 5)))
      (begin (set! test-pass (+ test-pass 1)) (printf "  PASS ttl/basic~n"))
      (begin (set! test-fail (+ test-fail 1))
             (printf "  FAIL ttl/basic~n    got: ~s~n" result))))

(set! test-count (+ test-count 1))
(let ([result (transform-top-level '((define x 5) (define y 10) (+ x y)))])
  (if (equal? result '(letrec ((x 5) (y 10)) (+ x y)))
      (begin (set! test-pass (+ test-pass 1)) (printf "  PASS ttl/multi-define~n"))
      (begin (set! test-fail (+ test-fail 1))
             (printf "  FAIL ttl/multi-define~n    got: ~s~n" result))))

(set! test-count (+ test-count 1))
(let ([result (transform-top-level '((+ 1 2)))])
  (if (equal? result '(+ 1 2))
      (begin (set! test-pass (+ test-pass 1)) (printf "  PASS ttl/no-define~n"))
      (begin (set! test-fail (+ test-fail 1))
             (printf "  FAIL ttl/no-define~n    got: ~s~n" result))))

;; --- Step 5 Summary ---
(printf "~n── Step 5 Summary ──~n")
(printf "  ~a/~a passed" test-pass test-count)
(if (> test-fail 0)
    (printf ", ~a FAILED~n" test-fail)
    (printf "~n"))
(when (> test-fail 0) (exit 1))

;; =========================================================================
;; Step 6 Tests: Vau Call-Site Specialization
;; =========================================================================

(printf "~n=== Seed3 Step 6: Vau Call-Site Codegen ===~n~n")

;; --- Specialize: and2 ---
(printf "── and2 specialization ──~n")
(test-run-env "and2/true-true"
  '(letrec ((and2 (vau (a b) e
                    (if (eval a e) (eval b e) #f))))
     (and2 #t 42))
  42)

(test-run-env "and2/true-false"
  '(letrec ((and2 (vau (a b) e
                    (if (eval a e) (eval b e) #f))))
     (and2 #t #f))
  #f)

(test-run-env "and2/false-short"
  '(letrec ((and2 (vau (a b) e
                    (if (eval a e) (eval b e) #f))))
     (and2 #f 42))
  #f)

;; --- Specialize: or2 ---
(printf "── or2 specialization ──~n")
(test-run-env "or2/false-val"
  '(letrec ((or2 (vau (a b) e
                   (let ((v (eval a e)))
                     (if v v (eval b e))))))
     (or2 #f 5))
  5)

(test-run-env "or2/true-val"
  '(letrec ((or2 (vau (a b) e
                   (let ((v (eval a e)))
                     (if v v (eval b e))))))
     (or2 42 5))
  42)

;; --- Specialize: when (dotted params / rest args) ---
(printf "── when specialization (dotted params) ──~n")
(test-run-env "when/true"
  '(letrec ((when (vau (test . body) e
                    (if (eval test e)
                        (eval (cons 'begin body) e)
                        #f))))
     (when #t 1 2))
  2)

(test-run-env "when/false"
  '(letrec ((when (vau (test . body) e
                    (if (eval test e)
                        (eval (cons 'begin body) e)
                        #f))))
     (when #f 1 2))
  #f)

;; --- Mixed vau + lambda program ---
(printf "── Mixed vau + lambda ──~n")
(test-run-env "mixed/and2-in-lambda"
  '(letrec ((and2 (vau (a b) e
                    (if (eval a e) (eval b e) #f)))
            (f (lambda (x y) (and2 x y))))
     (f #t 42))
  42)

(test-run-env "mixed/or2-in-lambda"
  '(letrec ((or2 (vau (a b) e
                   (let ((v (eval a e)))
                     (if v v (eval b e)))))
            (f (lambda (x y) (or2 x y))))
     (f #f 99))
  99)

;; --- FizzBuzz-like test ---
(printf "── FizzBuzz mini (vau + lambda) ──~n")
(test-run-env "fizzbuzz-mini"
  '(letrec ((and2 (vau (a b) e
                    (if (eval a e) (eval b e) #f)))
            (fizzbuzz-one
             (lambda (i)
               (let ((div3 (= (remainder i 3) 0))
                     (div5 (= (remainder i 5) 0)))
                 (if (and2 div3 div5)
                     'fizzbuzz
                     (if div3 'fizz
                         (if div5 'buzz i)))))))
     (list (fizzbuzz-one 15) (fizzbuzz-one 3)
           (fizzbuzz-one 5)  (fizzbuzz-one 7)))
  '(fizzbuzz fizz buzz 7))

;; --- Higher-order applicative: identity vs quote ---
(printf "── Higher-order applicative (identity vs quote) ──~n")
(test-run-env "ho-applicative/identity"
  '(let ((foo (lambda (bar) (bar (+ 2 2)))))
     (foo (lambda (x) x)))
  4)

(test-run-env "ho-applicative/quote-vau"
  '(let ((foo (lambda (bar) (bar (+ 2 2)))))
     (foo (vau (x) #f x)))
  '(+ 2 2))

(test-run-env "ho-applicative/mixed"
  '(letrec ((a (lambda (b) (b (+ 2 2)))))
     (list (a (lambda (x) x))
           (a (vau (x) #f x))))
  '(4 (+ 2 2)))

;; --- Step 6 Summary ---
(printf "~n── Step 6 Summary ──~n")
(printf "  ~a/~a passed" test-pass test-count)
(if (> test-fail 0)
    (printf ", ~a FAILED~n" test-fail)
    (printf "~n"))
(when (> test-fail 0) (exit 1))

;; =========================================================================
;; Final Summary
;; =========================================================================

(printf "~n══════════════════════════════════════~n")
(printf "  TOTAL: ~a/~a passed" test-pass test-count)
(if (> test-fail 0)
    (begin (printf ", ~a FAILED~n" test-fail) (exit 1))
    (printf "~n"))

(define dev!
  (lambda (active?)
    (unless active?
      (optimize-level 2)
      (collect-request-handler void))
    (when active?
      (compile-profile 'source))
    (import-notify active?)
    (generate-allocation-counts active?)
    (generate-covin-files active?)
    (generate-inspector-information active?)
    (generate-instruction-counts active?)
    (generate-interrupt-trap active?)
    (generate-procedure-source-information active?)
    (generate-profile-forms active?)
    (debug-on-exception active?)))

;; =========================================================================
;; L1 AST Definition
;; =========================================================================
;;
;; AST = (const <value>)                        ; number, boolean, string, null
;;     | (var <name>)                           ; symbol reference
;;     | (quot <datum>)                         ; quoted datum (not 'quote')
;;     | (if <AST> <AST> <AST>)                 ; conditional (always 3-arm)
;;     | (begin <AST> ...)                      ; sequencing
;;     | (let ((<name> <AST>) ...) <AST>)       ; local binding (single body)
;;     | (letrec ((<name> <AST>) ...) <AST>)    ; recursive binding
;;     | (vau <params> <ep> <AST>)              ; operative (sole abstraction)
;;     | (wrap <AST>)                           ; applicative wrapper
;;     | (eval <AST> <AST>)                     ; explicit evaluation
;;     | (call <AST> (<AST> ...))               ; application
;;     | (dyn-env)                              ; dynamic calling environment
;;
;; ep = #f          ; ignored (was _ or %ignore, or from lambda desugar)
;;    | <symbol>    ; live env-param binding

;; =========================================================================
;; Helpers
;; =========================================================================

;; Normalize environment parameter: _ and %ignore → #f (canonical ignored)
(define (normalize-ep e)
  (if (or (eq? e '_) (eq? e '%ignore))
      #f
      e))

;; filter-map: map + filter in one pass (not built into Chez)
(define (filter-map f lst)
  (cond [(null? lst) '()]
        [else (let ([v (f (car lst))])
                (if v (cons v (filter-map f (cdr lst)))
                    (filter-map f (cdr lst))))]))

;; Extract parameter names from a parameter tree.
;; Handles: symbol (rest), list (fixed), dotted list (fixed + rest).
(define (param-names p)
  (cond [(symbol? p) (list p)]
        [(null? p) '()]
        [(pair? p) (append (param-names (car p)) (param-names (cdr p)))]
        [else '()]))

;; =========================================================================
;; PASS 1: parse  (Source S-Expr → L1 AST)
;; =========================================================================
;;
;; No catamorphism — input is unstructured S-expressions.
;; SRFI-241 match is used for pattern dispatch; recursion is explicit.

(define (parse expr)
  (match expr
    ;; ---- Self-evaluating literals ----
    [,n (guard (number? n))  `(const ,n)]
    [,b (guard (boolean? b)) `(const ,b)]
    [,s (guard (string? s))  `(const ,s)]
    [,n (guard (null? n))    `(const ,n)]

    ;; ---- Symbol (variable reference) ----
    [,s (guard (symbol? s))  `(var ,s)]

    ;; ---- Quote ----
    ;; Guard workaround: 'quote' is special in SRFI-241 patterns
    [(,head ,d) (guard (eq? head 'quote))
     `(quot ,d)]

    ;; ---- Conditionals ----
    ;; Three-arm if (before two-arm for specificity)
    [(if ,t ,c ,a)
     `(if ,(parse t) ,(parse c) ,(parse a))]
    ;; Two-arm if: alt defaults to (const #f)
    [(if ,t ,c)
     `(if ,(parse t) ,(parse c) (const #f))]

    ;; ---- Begin ----
    [(begin . ,es)
     `(begin ,@(map parse es))]

    ;; ---- Let* (desugars to nested let) ----
    [(let* () ,body)
     (parse body)]
    [(let* () . ,bodies)
     (parse `(begin ,@bodies))]
    [(let* ((,name ,val) . ,rest) . ,bodies)
     (parse `(let ((,name ,val)) (let* ,rest ,@bodies)))]

    ;; ---- Let ----
    [(let ,bs ,body)
     `(let ,(map (lambda (b) (list (car b) (parse (cadr b)))) bs)
        ,(parse body))]
    [(let ,bs . ,bodies)
     `(let ,(map (lambda (b) (list (car b) (parse (cadr b)))) bs)
        ,(parse `(begin ,@bodies)))]

    ;; ---- Letrec ----
    [(letrec ,bs ,body)
     `(letrec ,(map (lambda (b) (list (car b) (parse (cadr b)))) bs)
        ,(parse body))]
    [(letrec ,bs . ,bodies)
     `(letrec ,(map (lambda (b) (list (car b) (parse (cadr b)))) bs)
        ,(parse `(begin ,@bodies)))]

    ;; ---- Lambda → wrap(vau)  [THE KEY DESUGARING] ----
    ;; (lambda params body ...) → (wrap (vau params #f parsed-body))
    [(lambda ,p ,body)
     `(wrap (vau ,p #f ,(parse body)))]
    [(lambda ,p . ,bodies)
     `(wrap (vau ,p #f ,(parse `(begin ,@bodies))))]

    ;; ---- Vau (operative — the core abstraction) ----
    [(vau ,p ,e ,body)
     `(vau ,p ,(normalize-ep e) ,(parse body))]
    [(vau ,p ,e . ,bodies)
     `(vau ,p ,(normalize-ep e) ,(parse `(begin ,@bodies)))]

    ;; ---- Eval ----
    [(eval ,e ,env)
     `(eval ,(parse e) ,(parse env))]

    ;; ---- Time ----
    [(time ,e)
     `(time ,(parse e))]

    ;; ---- Application (catch-all — MUST be last) ----
    [(,op . ,args)
     `(call ,(parse op) ,(map parse args))]

    ;; ---- Error ----
    [,x (error 'parse "unknown expression" x)]))

;; =========================================================================
;; AST → Source (catamorphism for testing/debugging)
;; =========================================================================
;;
;; Uses SRFI-241 catamorphisms: ,[var] auto-recurses via implicit loop.

(define (ast->src ast)
  (match ast
    [(const ,v) v]
    [(var ,n) n]
    [(quot ,d) `(quote ,d)]
    [(if ,[t] ,[c] ,[a]) `(if ,t ,c ,a)]
    [(begin ,[e] ...) `(begin ,@e)]
    [(let ((,n ,[v]) ...) ,[body]) `(let ,(map list n v) ,body)]
    [(letrec ((,n ,[v]) ...) ,[body]) `(letrec ,(map list n v) ,body)]
    ;; wrap(vau with #f ep) → lambda (roundtrip)
    [(wrap (vau ,p ,ep ,[body]))
     (guard (not ep))
     `(lambda ,p ,body)]
    ;; wrap of other
    [(wrap ,[inner]) `(wrap ,inner)]
    ;; raw vau
    [(vau ,p ,ep ,[body])
     `(vau ,p ,(or ep '_) ,body)]
    [(eval ,[e] ,[ev]) `(eval ,e ,ev)]
    [(time ,[e]) `(time ,e)]
    [(call ,[op] (,[a] ...)) `(,op ,@a)]
    [,_ '???]))

;; =========================================================================
;; PASS 2: annotate  (L1 AST → L2 AST)
;; =========================================================================
;;
;; Marks every (var <name>) as local or free:
;;   (var <name>)  →  (var <name> local|free)
;;
;; All other nodes unchanged structurally.
;;
;; Curried form: (annotate env) returns an AST → AST function.
;; SRFI-241 catamorphisms (,[var]) recurse with the same closed-over env,
;; which is correct for positions where the environment doesn't change
;; (if, begin, wrap, eval, call). Binding forms (let, letrec, vau) use
;; explicit recursion because they extend the environment.

(define (annotate env)
  (lambda (ast)
    (match ast
      ;; Leaves — no recursion needed
      [(const ,v)  `(const ,v)]
      [(var ,n)    `(var ,n ,(if (memq n env) 'local 'free))]
      [(quot ,d)   `(quot ,d)]

      ;; Structural recursion via catamorphism (env unchanged)
      [(if ,[t] ,[c] ,[a])      `(if ,t ,c ,a)]
      [(begin ,[e] ...)          `(begin ,@e)]
      [(wrap ,[inner])           `(wrap ,inner)]
      [(eval ,[e] ,[ev])         `(eval ,e ,ev)]
      [(time ,[e])               `(time ,e)]
      [(call ,[op] (,[a] ...))   `(call ,op ,a)]

      ;; Binding forms — explicit recursion (env changes)
      [(let ((,name ,rhs) ...) ,body)
       (let* ([new-rhs (map (annotate env) rhs)]
              [new-env (append name env)])
         `(let ,(map list name new-rhs)
            ,((annotate new-env) body)))]

      [(letrec ((,name ,rhs) ...) ,body)
       (let* ([new-env (append name env)]
              [new-rhs (map (annotate new-env) rhs)])
         `(letrec ,(map list name new-rhs)
            ,((annotate new-env) body)))]

      ;; vau — params + ep (if not #f) extend scope for body
      [(vau ,p ,ep ,body)
       (let* ([ps (param-names p)]
              [es (if ep (list ep) '())]
              [new-env (append ps es env)])
         `(vau ,p ,ep ,((annotate new-env) body)))]

      [,x (error 'annotate "unknown form" x)])))

;; =========================================================================
;; L2 AST → Source (for testing/debugging)
;; =========================================================================
;;
;; Like ast->src but handles the L2 (var name local|free) form.

(define (l2->src ast)
  (match ast
    [(const ,v) v]
    [(var ,n ,_) n]   ; drop annotation for roundtrip
    [(quot ,d) `(quote ,d)]
    [(if ,[t] ,[c] ,[a]) `(if ,t ,c ,a)]
    [(begin ,[e] ...) `(begin ,@e)]
    [(let ((,n ,[v]) ...) ,[body]) `(let ,(map list n v) ,body)]
    [(letrec ((,n ,[v]) ...) ,[body]) `(letrec ,(map list n v) ,body)]
    ;; wrap(vau with #f ep) → lambda (roundtrip)
    [(wrap (vau ,p ,ep ,[body]))
     (guard (not ep))
     `(lambda ,p ,body)]
    ;; wrap of other
    [(wrap ,[inner]) `(wrap ,inner)]
    ;; raw vau
    [(vau ,p ,ep ,[body])
     `(vau ,p ,(or ep '_) ,body)]
    [(eval ,[e] ,[ev]) `(eval ,e ,ev)]
    [(time ,[e]) `(time ,e)]
    [(call ,[op] (,[a] ...)) `(,op ,@a)]
    [,_ '???]))

;; =========================================================================
;; PASS 3: classify  (L2 AST → L3 AST)
;; =========================================================================
;;
;; Lowers (wrap (vau p #f body)) → (lam p body) when body is a pure
;; applicative: no eval nodes, no non-primitive free variables.
;; Genuine operatives (live ep or eval in body) stay as (vau ...).
;;
;; New L3 node:
;;   (lam <params> <AST>)   ; pure lambda (no env, no operative tag)

;; -------------------------------------------------------------------------
;; Predicates
;; -------------------------------------------------------------------------

;; Does the AST contain any (eval ...) node?
;; Pure catamorphism — structural search, env irrelevant.
(define (uses-eval? ast)
  (match ast
    [(eval ,_ ,_) #t]
    [(const ,_) #f]
    [(var ,_ ,_) #f]
    [(quot ,_) #f]
    [(if ,[t] ,[c] ,[a]) (or t c a)]
    [(begin ,[e] ...) (ormap values e)]
    [(wrap ,[inner]) inner]
    [(call ,[op] (,[a] ...)) (or op (ormap values a))]
    [(let ((,_ ,[v]) ...) ,[body]) (or (ormap values v) body)]
    [(letrec ((,_ ,[v]) ...) ,[body]) (or (ormap values v) body)]
    [(vau ,_ ,_ ,[body]) body]
    [,_ #f]))

;; Known primitives — free vars with these names are not "real" free vars.
(define *primitives*
  '(+ - * / = < > <= >= not null? pair? number? boolean? string? symbol?
    cons car cdr list map apply display newline error void
    eq? equal? zero? add1 sub1 length append reverse
    abs quotient remainder modulo
    even? odd? positive? negative?
    list? procedure?
    caar cadr cdar cddr
    memq memv member
    list-ref list-tail
    printf string? string-append string->number number->string
    iota
    current-nanoseconds
    exists for-all))

;; Does the AST contain any (var name free) where name is NOT a primitive?
(define (has-free-vars? ast)
  (match ast
    [(var ,n free) (not (memq n *primitives*))]
    [(var ,_ ,_) #f]
    [(const ,_) #f]
    [(quot ,_) #f]
    [(if ,[t] ,[c] ,[a]) (or t c a)]
    [(begin ,[e] ...) (ormap values e)]
    [(wrap ,[inner]) inner]
    [(eval ,[e] ,[ev]) (or e ev)]
    [(call ,[op] (,[a] ...)) (or op (ormap values a))]
    [(let ((,_ ,[v]) ...) ,[body]) (or (ormap values v) body)]
    [(letrec ((,_ ,[v]) ...) ,[body]) (or (ormap values v) body)]
    [(vau ,_ ,_ ,[body]) body]
    [,_ #f]))

;; Does the AST reference the dynamic environment?
;; Only checks for (dyn-env) nodes or (eval ...) nodes
(define (references-env? ast)
  (match ast
    [(dyn-env) #t]
    [(eval ,_ ,_) #t]
    [(const ,_) #f]
    [(var ,_ ,_) #f]
    [(quot ,_) #f]
    [(if ,[t] ,[c] ,[a]) (or t c a)]
    [(begin ,[e] ...) (ormap values e)]
    [(wrap ,[inner]) inner]
    [(lam ,_ ,[body]) body]
    [(vau ,_ ,_ ,[body]) body]
    [(vau ,_ ,_ ,[body] ,_) body]  ; L4 AST with BTA annotation
    [(time ,[e]) e]
    [(call ,[op] (,[a] ...)) (or op (ormap values a))]
    [(let ((,_ ,[v]) ...) ,[body]) (or (ormap values v) body)]
    [(letrec ((,_ ,[v]) ...) ,[body]) (or (ormap values v) body)]
    [,_ #f]))

;; -------------------------------------------------------------------------
;; classify pass
;; -------------------------------------------------------------------------

(define (classify ast)
  (match ast
    ;; THE KEY RULE: wrap(vau with #f ep) → lam if pure (no eval, no free vars)
    ;; Note: Functions with free vars but no env/eval usage are optimized in codegen
    [(wrap (vau ,p ,ep ,body))
     (guard (not ep))
     (let ([body* (classify body)])
       (if (and (not (uses-eval? body*))
                (not (has-free-vars? body*)))
           `(lam ,p ,body*)
           `(wrap (vau ,p #f ,body*))))]

    ;; Bare vau with live ep — genuine operative, just recurse into body
    [(vau ,p ,ep ,[body])
     `(vau ,p ,ep ,body)]

    ;; All other nodes — pure catamorphism
    [(const ,v) `(const ,v)]
    [(var ,n ,b) `(var ,n ,b)]
    [(quot ,d) `(quot ,d)]
    [(if ,[t] ,[c] ,[a]) `(if ,t ,c ,a)]
    [(begin ,[e] ...) `(begin ,@e)]
    [(eval ,[e] ,[ev]) `(eval ,e ,ev)]
    [(time ,[e]) `(time ,e)]
    [(call ,[op] (,[a] ...)) `(call ,op ,a)]
    [(let ((,n ,[v]) ...) ,[body]) `(let ,(map list n v) ,body)]
    [(letrec ((,n ,[v]) ...) ,[body]) `(letrec ,(map list n v) ,body)]
    [,x (error 'classify "unknown form" x)]))

;; =========================================================================
;; L3 AST → Source (for testing/debugging)
;; =========================================================================
;;
;; Like l2->src but adds the (lam ...) node → (lambda ...) for display.

(define (l3->src ast)
  (match ast
    [(const ,v) v]
    [(var ,n ,_) n]   ; drop annotation for roundtrip
    [(quot ,d) `(quote ,d)]
    [(if ,[t] ,[c] ,[a]) `(if ,t ,c ,a)]
    [(begin ,[e] ...) `(begin ,@e)]
    [(let ((,n ,[v]) ...) ,[body]) `(let ,(map list n v) ,body)]
    [(letrec ((,n ,[v]) ...) ,[body]) `(letrec ,(map list n v) ,body)]
    ;; lam → lambda (the new node)
    [(lam ,p ,[body]) `(lambda ,p ,body)]
    ;; wrap(vau with #f ep) → lambda (roundtrip)
    [(wrap (vau ,p ,ep ,[body]))
     (guard (not ep))
     `(lambda ,p ,body)]
    ;; wrap of other
    [(wrap ,[inner]) `(wrap ,inner)]
    ;; raw vau
    [(vau ,p ,ep ,[body])
     `(vau ,p ,(or ep '_) ,body)]
    [(eval ,[e] ,[ev]) `(eval ,e ,ev)]
    [(time ,[e]) `(time ,e)]
    [(call ,[op] (,[a] ...)) `(,op ,@a)]
    [,_ '???]))

;; =========================================================================
;; PASS 4: bta  (L3 AST → L4 AST)
;; =========================================================================
;;
;; Binding-Time Analysis for genuine operatives.
;;
;; Annotates each parameter of vau forms (where ep is live) with its
;; binding-time classification:
;;   static-eval   — param only appears in (eval param ep) patterns
;;   static-syntax — param is used as unevaluated syntax (or unused)
;;   dynamic       — param used in both eval and non-eval positions
;;
;; L4 AST change:
;;   (vau <params> <ep> <AST> <bta>)   ; bta = ((name bt) ...)
;;   where bt ∈ {static-eval, static-syntax, dynamic}
;;
;; Pure lambdas (lam) and wrapped impure applicatives (wrap(vau #f))
;; pass through unchanged.

;; -------------------------------------------------------------------------
;; Analysis helpers
;; -------------------------------------------------------------------------

;; Collect param names that appear in (eval (var name local) (var ep local))
;; Returns a list (may contain duplicates; we only care about membership).
(define (direct-eval-params ep-name param-set body)
  (define (walk ast)
    (match ast
      [(eval (var ,n local) (var ,e local))
       (guard (and (eq? e ep-name) (memq n param-set)))
       (list n)]
      [(const ,_) '()]
      [(var ,_ ,_) '()]
      [(quot ,_) '()]
      [(if ,[t] ,[c] ,[a]) (append t c a)]
      [(begin ,[e] ...) (apply append e)]
      [(eval ,[e] ,[ev]) (append e ev)]
      [(time ,[e]) e]
      [(call ,[op] (,[a] ...)) (apply append (cons op a))]
      [(let ((,_ ,[v]) ...) ,[body]) (apply append (append v (list body)))]
      [(letrec ((,_ ,[v]) ...) ,[body]) (apply append (append v (list body)))]
      [(lam ,_ ,[body]) body]
      [(wrap ,[inner]) inner]
      [(vau ,_ ,_ ,[body]) body]
      [,_ '()]))
  (walk body))

;; Collect param names that appear as (var name local) OUTSIDE eval patterns.
;; Skips occurrences in (eval (var n local) (var ep local)) patterns.
(define (bare-var-uses ep-name param-set body)
  (define (walk ast)
    (match ast
      ;; Direct eval of param — skip this entire node
      [(eval (var ,n local) (var ,e local))
       (guard (and (eq? e ep-name) (memq n param-set)))
       '()]
      ;; Param var — count it
      [(var ,n local)
       (guard (memq n param-set))
       (list n)]
      [(const ,_) '()]
      [(var ,_ ,_) '()]
      [(quot ,_) '()]
      [(if ,[t] ,[c] ,[a]) (append t c a)]
      [(begin ,[e] ...) (apply append e)]
      [(eval ,[e] ,[ev]) (append e ev)]
      [(time ,[e]) e]
      [(call ,[op] (,[a] ...)) (apply append (cons op a))]
      [(let ((,_ ,[v]) ...) ,[body]) (apply append (append v (list body)))]
      [(letrec ((,_ ,[v]) ...) ,[body]) (apply append (append v (list body)))]
      [(lam ,_ ,[body]) body]
      [(wrap ,[inner]) inner]
      [(vau ,_ ,_ ,[body]) body]
      [,_ '()]))
  (walk body))

;; Classify each param's binding time.
(define (param-binding-times params ep body)
  (let* ([names (param-names params)]
         [eval-set (direct-eval-params ep names body)]
         [bare-set (bare-var-uses ep names body)])
    (map (lambda (n)
           (list n (cond
                     [(and (memq n eval-set) (memq n bare-set)) 'dynamic]
                     [(memq n eval-set) 'static-eval]
                     [else 'static-syntax])))
         names)))

;; -------------------------------------------------------------------------
;; bta pass
;; -------------------------------------------------------------------------

(define (bta ast)
  (match ast
    ;; Genuine vau with live ep — analyze THEN recurse
    [(vau ,p ,ep ,body)
     (guard ep)
     (let* ([bt (param-binding-times p ep body)]
            [body* (bta body)])
       `(vau ,p ,ep ,body* ,bt))]

    ;; Vau with #f ep — just recurse into body
    [(vau ,p ,ep ,[body])
     (guard (not ep))
     `(vau ,p ,ep ,body)]

    ;; All other nodes — pure catamorphism
    [(const ,v) `(const ,v)]
    [(var ,n ,b) `(var ,n ,b)]
    [(quot ,d) `(quot ,d)]
    [(if ,[t] ,[c] ,[a]) `(if ,t ,c ,a)]
    [(begin ,[e] ...) `(begin ,@e)]
    [(eval ,[e] ,[ev]) `(eval ,e ,ev)]
    [(time ,[e]) `(time ,e)]
    [(call ,[op] (,[a] ...)) `(call ,op ,a)]
    [(lam ,p ,[body]) `(lam ,p ,body)]
    [(wrap ,[inner]) `(wrap ,inner)]
    [(let ((,n ,[v]) ...) ,[body]) `(let ,(map list n v) ,body)]
    [(letrec ((,n ,[v]) ...) ,[body]) `(letrec ,(map list n v) ,body)]
    [,x (error 'bta "unknown form" x)]))

;; =========================================================================
;; L4 AST → Source (for testing/debugging)
;; =========================================================================
;;
;; Like l3->src but handles the BTA-annotated vau (5-field).

(define (l4->src ast)
  (match ast
    [(const ,v) v]
    [(var ,n ,_) n]   ; drop annotation for roundtrip
    [(quot ,d) `(quote ,d)]
    [(if ,[t] ,[c] ,[a]) `(if ,t ,c ,a)]
    [(begin ,[e] ...) `(begin ,@e)]
    [(let ((,n ,[v]) ...) ,[body]) `(let ,(map list n v) ,body)]
    [(letrec ((,n ,[v]) ...) ,[body]) `(letrec ,(map list n v) ,body)]
    ;; lam → lambda
    [(lam ,p ,[body]) `(lambda ,p ,body)]
    ;; BTA-annotated vau (5-field) — drop bta for display
    [(vau ,p ,ep ,[body] ,bta)
     `(vau ,p ,(or ep '_) ,body)]
    ;; wrap(vau with #f ep) → lambda
    [(wrap (vau ,p ,ep ,[body]))
     (guard (not ep))
     `(lambda ,p ,body)]
    ;; wrap of other
    [(wrap ,[inner]) `(wrap ,inner)]
    ;; raw vau (4-field)
    [(vau ,p ,ep ,[body])
     `(vau ,p ,(or ep '_) ,body)]
    [(eval ,[e] ,[ev]) `(eval ,e ,ev)]
    [(time ,[e]) `(time ,e)]
    [(call ,[op] (,[a] ...)) `(,op ,@a)]
    [,_ '???]))

;; =========================================================================
;; PASS 5: codegen  (L4 AST → Scheme S-expression)
;; =========================================================================
;;
;; Context-aware code generation with call-site specialization for vau.
;;
;; ctx = alist of (name . info)
;;   info = 'direct       — pure lam, call as (name args...)
;;        | 'lambda       — impure wrap(vau), call as (name env args...)
;;        | (vau-info params ep body)  — operative, specialize at call sites
;;        | 'scheme-var   — lambda-bound var, no env needed
;;
;; For pure-lam programs (like nqueen-bench3.k), this is nearly identity:
;;   lam → lambda, call → application, var → name, const → value.
;;
;; For vau programs, the key insight is compile-time specialization:
;;   (and2 div3 div7) with body (if (eval a e) (eval b e) #f)
;;   → (if div3 div7 #f)  — exactly what syntax-rules produces.

;; -------------------------------------------------------------------------
;; Helpers
;; -------------------------------------------------------------------------

;; Check if a ctx entry is vau-info
(define (vau-info? info)
  (and (pair? info) (eq? (car info) 'vau-info)))

;; Recover source S-expression from L4 AST (for quoting syntax in specialize)
(define (ast->src* ast)
  (match ast
    [(const ,v) v]
    [(var ,n ,_) n]
    [(var ,n) n]
    [(quot ,d) `(quote ,d)]
    [(if ,t ,c ,a) `(if ,(ast->src* t) ,(ast->src* c) ,(ast->src* a))]
    [(begin ,e ...) `(begin ,@(map ast->src* e))]
    [(let ((,n ,v) ...) ,body)
     `(let ,(map (lambda (nm vl) (list nm (ast->src* vl))) n v)
        ,(ast->src* body))]
    [(letrec ((,n ,v) ...) ,body)
     `(letrec ,(map (lambda (nm vl) (list nm (ast->src* vl))) n v)
        ,(ast->src* body))]
    [(lam ,p ,body) `(lambda ,p ,(ast->src* body))]
    [(wrap (vau ,p #f ,body)) `(lambda ,p ,(ast->src* body))]
    [(wrap (vau ,p #f ,body ,_bta)) `(lambda ,p ,(ast->src* body))]
    [(wrap ,inner) `(wrap ,(ast->src* inner))]
    [(vau ,p ,ep ,body ,_bta) `(vau ,p ,(or ep '_) ,(ast->src* body))]
    [(vau ,p ,ep ,body) `(vau ,p ,(or ep '_) ,(ast->src* body))]
    [(eval ,e ,ev) `(eval ,(ast->src* e) ,(ast->src* ev))]
    [(time ,e) `(time ,(ast->src* e))]
    [(call ,op ,args) `(,(ast->src* op) ,@(map ast->src* args))]
    [(dyn-env) 'env]
    [,_ '???]))

;; --- Constant folding helpers ---

(define *foldable-primitives*
  '(car cdr caar cadr cdar cddr caaar caadr
    cons list append reverse length
    null? pair? number? symbol? boolean? string? eq? equal? not
    + - * quotient remainder modulo abs
    = < > <= >=))

;; Is this AST node a compile-time-known value?
(define (static-value? ast)
  (match ast
    [(const ,v) #t]
    [(quot ,d) #t]
    [,_ #f]))

;; Extract the runtime value from a static AST node
(define (static-value ast)
  (match ast
    [(const ,v) v]
    [(quot ,d) d]))

;; Wrap a runtime value back into the appropriate AST node
(define (value->ast v)
  (if (or (number? v) (boolean? v) (string? v) (null? v))
      `(const ,v)
      `(quot ,v)))

;; Try to fold (name arg1 arg2 ...) at compile time.
;; Returns AST node or #f.
(define (try-fold-call name arg-asts)
  (and (memq name *foldable-primitives*)
       (for-all static-value? arg-asts)
       (let ([vals (map static-value arg-asts)])
         (call/cc (lambda (k)
           (with-exception-handler
             (lambda (c) (k #f))
             (lambda ()
               (value->ast (apply (eval name) vals)))))))))

;; Bind vau params to args for substitution, handling dotted params.
;; Returns alist of (param-name . arg-ast).
;; For (vau (a b) e ...) called with (x y): ((a . x-ast) (b . y-ast))
;; For (vau (a . rest) e ...) called with (x y z): ((a . x-ast) (rest . rest-list))
;; where rest-list is a (quot (y-src z-src)) node.
(define (bind-param-to-args params args)
  (cond
    [(null? params) '()]
    [(symbol? params)
     ;; Rest param — collect remaining args as a quoted list of source forms
     (list (cons params `(quot ,(map ast->src* args))))]
    [(pair? params)
     (cons (cons (car params) (car args))
           (bind-param-to-args (cdr params) (cdr args)))]))

;; -------------------------------------------------------------------------
;; Specialize: partial evaluation of vau bodies at compile time
;; -------------------------------------------------------------------------
;;
;; Core of the first Futamura projection for vau macros.
;; Given a vau body, parameter substitution, and environment parameter name,
;; produces specialized Scheme code.
;;
;; Key rules:
;;   (eval (var param local) (var ep local)) where param in subst → compile arg
;;   (var param local) where param in subst → quote as syntax
;;   (var ep local) → env
;;   (eval <general-expr> (var ep local)) → (seed-eval <spec'd-expr> env)

(define (free-symbols sexp)
  (cond
    [(symbol? sexp)
     (if (memq sexp '(quote if let letrec lambda begin define vau wrap eval
                       guard and or cond else not))
         '() (list sexp))]
    [(pair? sexp)
     (cond
       ;; (quote ...) — no free symbols
       [(eq? (car sexp) 'quote) '()]
       ;; (lambda (params) body) — exclude params from body
       [(eq? (car sexp) 'lambda)
        (let ([params (cadr sexp)]
              [body (cddr sexp)])
          (let ([param-names (let loop ([p params])
                               (cond [(null? p) '()]
                                     [(symbol? p) (list p)]
                                     [(pair? p) (cons (car p) (loop (cdr p)))]
                                     [else '()]))])
            (filter (lambda (s) (not (memq s param-names)))
                    (free-symbols body))))]
       ;; (let ((n v) ...) body) — exclude binding names from body
       [(memq (car sexp) '(let letrec))
        (let ([binds (cadr sexp)]
              [body (cddr sexp)])
          (if (and (pair? binds) (pair? (car binds)))
              (let ([names (map car binds)]
                    [vals-syms (free-symbols (map cadr binds))]
                    [body-syms (free-symbols body)])
                (append vals-syms
                        (filter (lambda (s)
                                  (and (not (memq s vals-syms))
                                       (not (memq s names))))
                                body-syms)))
              ;; Fallback for malformed let
              (let ([l (free-symbols (car sexp))] [r (free-symbols (cdr sexp))])
                (append l (filter (lambda (s) (not (memq s l))) r)))))]
       [else
        (let ([l (free-symbols (car sexp))] [r (free-symbols (cdr sexp))])
          (append l (filter (lambda (s) (not (memq s l))) r)))])]
    [else '()]))

(define (compile-eval-body body-sexp binds-ast env-ast ctx lenv ifuel)
  (let* ([all-vars (free-symbols body-sexp)]
         ;; Only bind vars that are NOT primitives or known free bindings
         ;; Pattern variables are not in the global scope
         [vars (filter (lambda (v) (not (memq v *primitives*))) all-vars)]
         [scope (map (lambda (v) (cons v 'local)) vars)]
         [parsed (parse body-sexp)]
         [annotated ((annotate scope) parsed)]
         [let-binds (map (lambda (v)
                           (list v `(call (var cdr free)
                                     ((call (var assq free)
                                        ((quot ,v) ,binds-ast))))))
                         vars)]
         [body-ast (spec annotated '() #f ctx lenv ifuel)])
    (if (null? let-binds) body-ast `(let ,let-binds ,body-ast))))

(define (inline-lambda lam-ast arg-asts subst ep ctx lenv ifuel)
  (match lam-ast
    [(lam ,params ,body)
     (guard (list? params) (= (length params) (length arg-asts)))
     ;; Filter subst entries shadowed by lambda params to prevent capture
     (let ([clean-subst (remp (lambda (s) (memq (car s) params)) subst)])
       (let loop ([ps params] [as arg-asts] [new-subst clean-subst] [kept '()])
       (if (null? ps)
           (let ([body* (spec body new-subst ep ctx lenv ifuel)])
             (if (null? kept) body* `(let ,(reverse kept) ,body*)))
           (if (static-value? (car as))
               (loop (cdr ps) (cdr as) (cons (cons (car ps) (car as)) new-subst) kept)
               (loop (cdr ps) (cdr as) new-subst (cons (list (car ps) (car as)) kept))))))]
    [,_ #f]))

;; =========================================================================
;; Alist Fusion: eliminate build+destructure in compiled match
;; =========================================================================

;; Check if a match expression can be fully handled by thread-body.
;; Returns #t only if all leaf positions are (var _ local), (quot _), or (const #f).
(define (fusible-match? expr)
  (match expr
    ;; Rule 1 pattern: cons-bind + truthy-test
    [(let ((,x (call (var cons free)
                 ((call (var cons free) ((quot ,_) ,_val)) ,_prev))))
       (if (var ,x2 local) ,cont (const #f)))
     (guard (eq? x x2))
     (fusible-match? cont)]
    ;; Rule 1b pattern: let-wrapped cons-bind + truthy-test
    [(let ((,x (let ((,_v ,_e))
                 (call (var cons free)
                   ((call (var cons free) ((quot ,_) ,_body)) ,_prev)))))
       (if (var ,x2 local) ,cont (const #f)))
     (guard (eq? x x2))
     (fusible-match? cont)]
    ;; Rule 2 pattern: non-cons bind + truthy-test
    [(let ((,x ,_expr)) (if (var ,x2 local) ,cont (const #f)))
     (guard (eq? x x2))
     (fusible-match? cont)]
    ;; Rule 3 pattern: bare cons pair
    [(call (var cons free)
       ((call (var cons free) ((quot ,_) ,_val)) ,prev))
     (fusible-match? prev)]
    ;; Rule 4: structural if
    [(if ,_t ,c ,a)
     (and (fusible-match? c) (fusible-match? a))]
    ;; Rule 5: structural let
    [(let ((,_v ,_e)) ,rest)
     (fusible-match? rest)]
    ;; Rule 6: success leaf — variable
    [(var ,_ local) #t]
    ;; Rule 7: success leaf — quoted value
    [(quot ,_) #t]
    ;; Rule 8: failure leaf
    [(const #f) #t]
    ;; Anything else: not fusible
    [,_ #f]))

;; Check if AST contains (call (var assq free) ((quot _) (var BINDS-NAME local)))
(define (has-assq-refs? ast binds-name)
  (match ast
    [(call (var assq free) ((quot ,_) (var ,n local)))
     (eq? n binds-name)]
    [(let ((,_ ,vs) ...) ,body)
     (or (exists (lambda (v) (has-assq-refs? v binds-name)) vs)
         (has-assq-refs? body binds-name))]
    [(if ,t ,c ,a) (or (has-assq-refs? t binds-name)
                       (has-assq-refs? c binds-name)
                       (has-assq-refs? a binds-name))]
    [(call ,fn ,args) (or (has-assq-refs? fn binds-name)
                          (exists (lambda (a) (has-assq-refs? a binds-name)) args))]
    [(letrec ((,_ ,vs) ...) ,body)
     (or (exists (lambda (v) (has-assq-refs? v binds-name)) vs)
         (has-assq-refs? body binds-name))]
    [,_ #f]))

;; Collect all symbol names referenced via (cdr (assq 'SYM binds))
(define (collect-assq-syms ast binds-name)
  (match ast
    [(call (var cdr free) ((call (var assq free) ((quot ,sym) (var ,bn local)))))
     (guard (eq? bn binds-name))
     (list sym)]
    [(let ((,_ ,vs) ...) ,body)
     (append (apply append (map (lambda (v) (collect-assq-syms v binds-name)) vs))
             (collect-assq-syms body binds-name))]
    [(if ,t ,c ,a) (append (collect-assq-syms t binds-name)
                           (collect-assq-syms c binds-name)
                           (collect-assq-syms a binds-name))]
    [(call ,fn ,args) (append (collect-assq-syms fn binds-name)
                              (apply append (map (lambda (a) (collect-assq-syms a binds-name)) args)))]
    [(letrec ((,_ ,vs) ...) ,body)
     (append (apply append (map (lambda (v) (collect-assq-syms v binds-name)) vs))
             (collect-assq-syms body binds-name))]
    [,_ '()]))

;; Replace (cdr (assq 'SYM binds)) with (var SYM local) throughout AST
(define (replace-assq-refs ast binds-name)
  (match ast
    ;; The exact pattern: (cdr (assq 'SYM binds))
    [(call (var cdr free) ((call (var assq free) ((quot ,sym) (var ,bn local)))))
     (guard (eq? bn binds-name))
     `(var ,sym local)]
    ;; Recurse into all compound forms
    [(let ((,ns ,vs) ...) ,body)
     `(let ,(map list ns (map (lambda (v) (replace-assq-refs v binds-name)) vs))
        ,(replace-assq-refs body binds-name))]
    [(if ,t ,c ,a)
     `(if ,(replace-assq-refs t binds-name)
          ,(replace-assq-refs c binds-name)
          ,(replace-assq-refs a binds-name))]
    [(call ,fn ,args)
     `(call ,(replace-assq-refs fn binds-name)
            ,(map (lambda (a) (replace-assq-refs a binds-name)) args))]
    [(letrec ((,ns ,vs) ...) ,body)
     `(letrec ,(map list ns (map (lambda (v) (replace-assq-refs v binds-name)) vs))
        ,(replace-assq-refs body binds-name))]
    [,_ ast]))

;; Convert (var SYM free) to (var SYM local) for symbols in the given set.
;; This fixes annotations after fusion: variables that were free (referencing
;; the compile-eval-body let) become local once thread-body binds them directly.
(define (fix-free-to-local ast syms)
  (match ast
    [(var ,n free) (if (memq n syms) `(var ,n local) ast)]
    [(var ,_ ,_) ast]
    [(const ,_) ast]
    [(quot ,_) ast]
    [(dyn-env) ast]
    [(if ,t ,c ,a)
     `(if ,(fix-free-to-local t syms)
          ,(fix-free-to-local c syms)
          ,(fix-free-to-local a syms))]
    [(let ((,ns ,vs) ...) ,body)
     `(let ,(map list ns (map (lambda (v) (fix-free-to-local v syms)) vs))
        ,(fix-free-to-local body syms))]
    [(call ,fn ,args)
     `(call ,(fix-free-to-local fn syms)
            ,(map (lambda (a) (fix-free-to-local a syms)) args))]
    [(letrec ((,ns ,vs) ...) ,body)
     `(letrec ,(map list ns (map (lambda (v) (fix-free-to-local v syms)) vs))
        ,(fix-free-to-local body syms))]
    [(lam ,params ,body)
     `(lam ,params ,(fix-free-to-local body syms))]
    [(wrap (vau ,p ,e ,b))
     `(wrap (vau ,p ,e ,(fix-free-to-local b syms)))]
    [(wrap (vau ,p ,e ,b ,bta))
     `(wrap (vau ,p ,e ,(fix-free-to-local b syms) ,bta))]
    [,_ ast]))

;; Substitute all occurrences of (var NAME local) with REPLACEMENT in AST.
;; Stops at binding forms that shadow NAME.
(define (subst-var-in-ast ast name replacement)
  (match ast
    [(var ,n local) (if (eq? n name) replacement ast)]
    [(var ,_ free) ast]
    [(const ,_) ast]
    [(quot ,_) ast]
    [(dyn-env) ast]
    [(if ,t ,c ,a)
     `(if ,(subst-var-in-ast t name replacement)
          ,(subst-var-in-ast c name replacement)
          ,(subst-var-in-ast a name replacement))]
    [(let ((,ns ,vs) ...) ,body)
     (let ([vs* (map (lambda (v) (subst-var-in-ast v name replacement)) vs)])
       (if (memq name ns)
           `(let ,(map list ns vs*) ,body)       ;; name is shadowed in body
           `(let ,(map list ns vs*) ,(subst-var-in-ast body name replacement))))]
    [(call ,fn ,args)
     `(call ,(subst-var-in-ast fn name replacement)
            ,(map (lambda (a) (subst-var-in-ast a name replacement)) args))]
    [(letrec ((,ns ,vs) ...) ,body)
     (if (memq name ns)
         ast                                     ;; name is shadowed
         `(letrec ,(map list ns (map (lambda (v) (subst-var-in-ast v name replacement)) vs))
            ,(subst-var-in-ast body name replacement)))]
    [(lam ,params ,body)
     (if (memq name params)
         ast                                     ;; name is shadowed
         `(lam ,params ,(subst-var-in-ast body name replacement)))]
    [,_ ast]))

;; Thread success body into match success leaves, fail into failure leaves.
;; Eliminates cons pair construction and cons-truthy tests.
(define (thread-body expr success fail)
  (match expr
    ;; Rule 1: cons-bind + truthy-test → direct variable binding
    [(let ((,x (call (var cons free)
                 ((call (var cons free) ((quot ,sym) ,val)) ,_prev))))
       (if (var ,x2 local) ,cont (const #f)))
     (guard (eq? x x2))
     `(let ((,sym ,val)) ,(thread-body cont success fail))]

    ;; Rule 1b: let-wrapped cons-bind + truthy-test
    ;; (let ((x (let ((v e)) (cons (cons 'sym body) prev)))) (if x cont #f))
    ;; → inline v→e in body, bind sym directly, thread cont (stays in outer scope)
    [(let ((,x (let ((,v ,e))
                 (call (var cons free)
                   ((call (var cons free) ((quot ,sym) ,body)) ,_prev)))))
       (if (var ,x2 local) ,cont (const #f)))
     (guard (eq? x x2))
     (let ([body* (subst-var-in-ast body v e)])
       `(let ((,sym ,body*)) ,(thread-body cont success fail)))]

    ;; Rule 2: non-cons bind + truthy-test → convert to if
    [(let ((,x ,expr*)) (if (var ,x2 local) ,cont (const #f)))
     (guard (eq? x x2))
     `(if ,expr* ,(thread-body cont success fail) ,fail)]

    ;; Rule 3: bare cons pair (e.g., guard clause with ,[n] pattern)
    [(call (var cons free)
       ((call (var cons free) ((quot ,sym) ,val)) ,prev))
     `(let ((,sym ,val)) ,(thread-body prev success fail))]

    ;; Rule 4: structural if
    [(if ,t ,c ,a)
     `(if ,t ,(thread-body c success fail) ,(thread-body a success fail))]

    ;; Rule 5: structural let
    [(let ((,v ,e)) ,rest)
     `(let ((,v ,e)) ,(thread-body rest success fail))]

    ;; Rule 6: success leaf — variable (accumulated alist)
    [(var ,_ local) success]

    ;; Rule 7: success leaf — quoted value (empty alist '())
    [(quot ,_) success]

    ;; Rule 8: failure leaf
    [(const #f) fail]

    ;; Fallthrough: leave unchanged
    [,_ expr]))

;; Walk full AST. When we find (let ([binds MATCH]) (if binds SUCCESS FAIL))
;; where SUCCESS contains assq refs to binds, fuse them.
(define (fuse-alist-lets ast)
  (match ast
    ;; Detect: (let ([binds MATCH]) (if binds SUCCESS FAIL))
    [(let ((,binds ,match-expr))
       (if (var ,binds2 local) ,success ,fail-expr))
     (guard (eq? binds binds2) (has-assq-refs? success binds) (fusible-match? match-expr))
     (let* ([bound-syms (collect-assq-syms success binds)]
            [success-clean (fix-free-to-local (replace-assq-refs success binds) bound-syms)]
            [match* (fuse-alist-lets match-expr)]
            [fail* (fuse-alist-lets fail-expr)])
       (thread-body match* success-clean fail*))]

    ;; Recurse into compound forms
    [(let ((,ns ,vs) ...) ,body)
     `(let ,(map list ns (map fuse-alist-lets vs))
        ,(fuse-alist-lets body))]
    [(if ,t ,c ,a)
     `(if ,(fuse-alist-lets t) ,(fuse-alist-lets c) ,(fuse-alist-lets a))]
    [(letrec ((,ns ,vs) ...) ,body)
     `(letrec ,(map list ns (map fuse-alist-lets vs))
        ,(fuse-alist-lets body))]
    [(call ,fn ,args)
     `(call ,(fuse-alist-lets fn) ,(map fuse-alist-lets args))]
    [(lam ,params ,body) `(lam ,params ,(fuse-alist-lets body))]
    [(wrap (vau ,p ,e ,b)) `(wrap (vau ,p ,e ,(fuse-alist-lets b)))]
    [(wrap (vau ,p ,e ,b ,bta)) `(wrap (vau ,p ,e ,(fuse-alist-lets b) ,bta))]
    [,_ ast]))

(define (specialize body params args ep ctx)
  (let* ([subst (bind-param-to-args params args)]
         [lenv (filter-map
                 (lambda (entry)
                   (and (pair? (cdr entry))
                        (eq? (cadr entry) 'direct)
                        (let ([ast (caddr entry)])
                          (match ast
                            [(lam ,p ,b) (cons (car entry) ast)]
                            [(wrap (vau ,p #f ,b)) (cons (car entry) `(lam ,p ,b))]
                            [(wrap (vau ,p #f ,b ,_bta)) (cons (car entry) `(lam ,p ,b))]
                            [,_ #f]))))
                 ctx)]
         [ast (spec body subst ep ctx lenv 100)])
    ;; Iterate with empty subst until fixed point (or fuel exhausted)
    (let loop ([ast ast] [fuel 10])
      (if (zero? fuel) ast
          (let* ([ast* (spec ast '() #f ctx lenv 100)]
                 [ast** (fuse-alist-lets ast*)])
            (if (equal? ast** ast) ast
                (loop ast** (- fuel 1))))))))

(define (spec ast subst ep ctx lenv ifuel)
  (match ast
    ;; Constants — pass through (already AST)
    [(const ,v) ast]

    ;; Quoted datum — pass through
    [(quot ,d) ast]

    ;; Dynamic environment — pass through
    [(dyn-env) ast]

    ;; Local variable
    [(var ,n local)
     (cond
       ;; Parameter in subst → quote the syntax (vau operands),
       ;; or return alias directly (copy-propagation)
       [(assq n subst)
        => (lambda (entry)
             (let ([val (cdr entry)])
               (cond
                 [(and (pair? val) (eq? (car val) 'alias))
                  (cadr val)]                        ;; copy-prop: return var directly
                 [(and (pair? val) (eq? (car val) 'quot))
                  val]                               ;; already (quot d)
                 [else
                  `(quot ,(ast->src* val))])))]      ;; vau operand: quote it
       ;; Environment param → dynamic env
       [(eq? n ep) '(dyn-env)]
       ;; Other local → keep as-is
       [else ast])]

    ;; Free variable — pass through
    [(var ,n free) ast]

    ;; Static eval: (eval param-ref ep-ref) → compile the arg directly
    [(eval (var ,n local) (var ,e local))
     (guard (eq? e ep))
     (let ([entry (assq n subst)])
       (if entry
           (let ([v (cdr entry)])                    ;; return the AST itself (static eval)
             (if (and (pair? v) (eq? (car v) 'alias))
                 (cadr v) v))
           `(eval (var ,n local) (dyn-env))))]       ;; fallback: dynamic eval

    ;; General eval with ep — spec without lenv to preserve call structure
    ;; (allows compile-eval-body rule to fire on subsequent passes)
    [(eval ,expr (var ,e local))
     (guard (eq? e ep))
     `(eval ,(spec expr subst ep ctx '() ifuel) (dyn-env))]

    ;; Eval of make-let with static body → compile directly
    [(eval (call (var ,ml local) (,binds-ast (quot ,body-sexp))) (dyn-env))
     (guard (eq? ml 'make-let))
     (let ([binds* (spec binds-ast subst ep ctx lenv ifuel)])
       (compile-eval-body body-sexp binds* '(dyn-env) ctx lenv ifuel))]

    ;; Eval with different env — spec expr without lenv to preserve call structure
    [(eval ,expr ,env-expr)
     `(eval ,(spec expr subst ep ctx '() ifuel)
            ,(spec env-expr subst ep ctx lenv ifuel))]

    ;; If — specialize + fold constant tests
    [(if ,t ,c ,a)
     (let ([t* (spec t subst ep ctx lenv ifuel)])
       (cond
         ;; Constant true → select consequent
         [(and (static-value? t*)
               (static-value t*))                   ;; truthy (non-#f)
          (spec c subst ep ctx lenv ifuel)]
         ;; Constant false → select alternative
         [(and (static-value? t*)
               (not (static-value t*)))             ;; #f
          (spec a subst ep ctx lenv ifuel)]
         ;; Dynamic → keep if
         [else
          `(if ,t* ,(spec c subst ep ctx lenv ifuel)
                   ,(spec a subst ep ctx lenv ifuel))]))]

    ;; Begin — specialize + collapse
    [(begin ,es ...)
     (let ([es* (map (lambda (e) (spec e subst ep ctx lenv ifuel)) es)])
       (if (= (length es*) 1)
           (car es*)
           `(begin ,@es*)))]

    ;; Let — specialize + propagate static bindings
    [(let ((,names ,vals) ...) ,body)
     (let loop ([ns names] [vs vals] [sub subst] [kept '()])
       (if (null? ns)
           ;; Remove subst entries shadowed by dynamic let bindings
           ;; Also remove entries whose substituted value references a rebound name
           ;; (needed for safe copy propagation of aliases like [y (var x local)])
           (let* ([kept-names (map car kept)]
                  [body-sub (if (null? kept-names) sub
                                (remp (lambda (s)
                                        (or (memq (car s) kept-names)
                                            (let ([v (cdr s)])
                                              ;; Check both direct (var n local) and (alias (var n local))
                                              (let ([v* (if (and (pair? v) (eq? (car v) 'alias))
                                                            (cadr v) v)])
                                                (and (pair? v*) (eq? (car v*) 'var)
                                                     (pair? (cdr v*))
                                                     (memq (cadr v*) kept-names))))))
                                      sub))]
                  [body* (spec body body-sub ep ctx lenv ifuel)])
             (if (null? kept)
                 body*                              ;; all bindings eliminated
                 `(let ,(reverse kept) ,body*)))
           (let ([v* (spec (car vs) sub ep ctx lenv ifuel)])
             (if (static-value? v*)
                 ;; Static → fold into subst, drop binding
                 (loop (cdr ns) (cdr vs)
                       (cons (cons (car ns) v*) sub)
                       kept)
                 ;; Dynamic → copy-propagate local var aliases [y (var x local)]
                 (if (and (pair? v*) (eq? (car v*) 'var)
                          (pair? (cdr v*))
                          (pair? (cddr v*)) (eq? (caddr v*) 'local))
                     ;; Alias: substitute y → (var x local) in body, drop binding
                     ;; Use (alias ...) tag to bypass vau-operand quoting in var handler
                     (loop (cdr ns) (cdr vs)
                           (cons (cons (car ns) (list 'alias v*)) sub) kept)
                     (loop (cdr ns) (cdr vs) sub
                           (cons (list (car ns) v*) kept)))))))]

    ;; Call to free (primitive) — specialize args + constant fold
    [(call (var ,n free) ,args)
     (let ([arg-asts (map (lambda (a) (spec a subst ep ctx lenv ifuel)) args)])
       (or (try-fold-call n arg-asts)
           `(call (var ,n free) ,arg-asts)))]

    ;; Call to local — specialize args + inline from lenv
    [(call (var ,n local) ,args)
     (let ([arg-asts (map (lambda (a) (spec a subst ep ctx lenv ifuel)) args)])
       (cond
         [(assq n subst)
          => (lambda (entry)
               (let ([v (cdr entry)])
                 `(call ,(if (and (pair? v) (eq? (car v) 'alias)) (cadr v) v)
                         ,arg-asts)))]
         [(and (> ifuel 0) (assq n lenv)
               (exists (lambda (a)
                         (and (static-value? a)
                              ;; Exclude (quot ()) — it triggers inlining explosion with
                              ;; mutually-recursive functions using accumulator patterns
                              ;; (e.g., pmatch/pmatch-elts where acc starts as '()).
                              (not (equal? a '(quot ())))))
                       arg-asts))
          (let ([lam-ast (cdr (assq n lenv))])
            (or (inline-lambda lam-ast arg-asts subst ep ctx lenv (- ifuel 1))
                `(call (var ,n local) ,arg-asts)))]
         [else `(call (var ,n local) ,arg-asts)]))]

    ;; General call fallback
    [(call ,op ,args)
     (let ([op* (spec op subst ep ctx lenv ifuel)]
           [arg-asts (map (lambda (a) (spec a subst ep ctx lenv ifuel)) args)])
       `(call ,op* ,arg-asts))]

    ;; Letrec — specialize bindings and body, populate lenv
    ;; Two-pass: first spec vals with outer lenv, then rebuild lenv
    ;; from specialized vals and re-spec vals with inner lenv (empty subst
    ;; since substitutions were already applied).
    [(letrec ((,names ,vals) ...) ,body)
     (let* ([vals1 (map (lambda (v) (spec v subst ep ctx lenv ifuel)) vals)]
            [inner-lenv (append
                          (filter-map
                            (lambda (nv)
                              (let ([n (car nv)] [v (cdr nv)])
                                (match v
                                  [(lam ,p ,b) (cons n v)]
                                  [(wrap (vau ,p #f ,b)) (cons n `(lam ,p ,b))]
                                  [,_ #f])))
                            (map cons names vals1))
                          lenv)]
            [vals* (if (null? inner-lenv) vals1
                       (map (lambda (v) (spec v '() #f ctx inner-lenv ifuel)) vals1))]
            [new-lenv (if (equal? vals* vals1) inner-lenv
                          (append
                            (filter-map
                              (lambda (nv)
                                (let ([n (car nv)] [v (cdr nv)])
                                  (match v
                                    [(lam ,p ,b) (cons n v)]
                                    [(wrap (vau ,p #f ,b)) (cons n `(lam ,p ,b))]
                                    [,_ #f])))
                              (map cons names vals*))
                            lenv))])
       `(letrec ,(map list names vals*)
          ,(spec body subst ep ctx new-lenv ifuel)))]

    ;; Pure lambda (lam)
    [(lam ,p ,body)
     `(lam ,p ,(spec body subst ep ctx lenv ifuel))]

    ;; wrap(vau with #f ep) — specialize body, keep as wrap(vau)
    [(wrap (vau ,p #f ,body))
     (let* ([all-params (param-names p)]
            [new-ctx (append (map (lambda (n) (cons n 'scheme-var)) all-params) ctx)]
            [body* (spec body subst ep new-ctx lenv ifuel)])
       `(wrap (vau ,p #f ,body*)))]

    ;; wrap(vau with #f ep, BTA)
    [(wrap (vau ,p #f ,body ,bta))
     (let* ([all-params (param-names p)]
            [new-ctx (append (map (lambda (n) (cons n 'scheme-var)) all-params) ctx)]
            [body* (spec body subst ep new-ctx lenv ifuel)])
       `(wrap (vau ,p #f ,body* ,bta)))]

    ;; wrap(vau with live ep)
    [(wrap (vau ,p ,wep ,body))
     (guard wep)
     (let* ([all-params (param-names p)]
            [new-ctx (append (map (lambda (n) (cons n 'scheme-var)) all-params) ctx)]
            [body* (spec body subst ep new-ctx lenv ifuel)])
       `(wrap (vau ,p ,wep ,body*)))]

    ;; wrap(vau with live ep, BTA)
    [(wrap (vau ,p ,wep ,body ,bta))
     (guard wep)
     (let* ([all-params (param-names p)]
            [new-ctx (append (map (lambda (n) (cons n 'scheme-var)) all-params) ctx)]
            [body* (spec body subst ep new-ctx lenv ifuel)])
       `(wrap (vau ,p ,wep ,body* ,bta)))]

    ;; Time — specialize the timed expression
    [(time ,e)
     `(time ,(spec e subst ep ctx lenv ifuel))]

    ;; Anything else — pass through unchanged
    [,_ ast]))

;; -------------------------------------------------------------------------
;; Context-aware codegen
;; -------------------------------------------------------------------------

(define (codegen ast)
  (codegen* ast '()))

(define (codegen* ast ctx)
  (match ast
    [(const ,v)
     (if (or (null? v) (string? v)) `',v v)]
    [(var ,n local) n]
    [(var ,n free) n]
    [(quot ,d) `',d]
    [(if ,t ,c ,a)
     (let ([ct (codegen* t ctx)] [cc (codegen* c ctx)] [ca (codegen* a ctx)])
       (cond
         [(and (eq? cc #t) (eq? ca #f)) ct]
         [(eq? cc #t)
          ;; Flatten nested ors: (or x (or y z)) → (or x y z)
          (if (and (pair? ca) (eq? (car ca) 'or))
              `(or ,ct ,@(cdr ca))
              `(or ,ct ,ca))]
         [(eq? ca #f)
          ;; Flatten nested ands: (and x (and y z)) → (and x y z)
          (if (and (pair? cc) (eq? (car cc) 'and))
              `(and ,ct ,@(cdr cc))
              `(and ,ct ,cc))]
         [else `(if ,ct ,cc ,ca)]))]
    [(begin ,e ...) `(begin ,@(map (lambda (x) (codegen* x ctx)) e))]
    [(lam ,p ,body) `(lambda ,p ,(codegen* body ctx))]
    [(let ((,names ,vals) ...) ,body)
     `(let ,(map (lambda (n v) (list n (codegen* v ctx))) names vals)
        ,(codegen* body ctx))]

    ;; Named-let: (letrec ([f (lam (a b) body)]) (call f (x y))) → (let f ([a x] [b y]) body)
    [(letrec ((,names ,vals) ...) (call (var ,callname local) ,callargs))
     (guard (and (= (length names) 1)
                 (eq? (car names) callname)
                 (= (length callargs) (length (match (car vals) [(lam ,p ,_) p] [,_ '()])))
                 (match (car vals) [(lam ,p ,_) (list? p)] [,_ #f])))
     (let* ([name (car names)]
            [val (car vals)])
       (match val
         [(lam ,params ,lam-body)
          (let* ([new-ctx (cons (cons name (list 'direct val)) ctx)]
                 [compiled-args (map (lambda (a) (codegen* a ctx)) callargs)]
                 [compiled-body (codegen* lam-body new-ctx)])
            `(let ,name ,(map list params compiled-args) ,compiled-body))]))]

    ;; Letrec — classify each binding and build ctx
    [(letrec ((,names ,vals) ...) ,body)
     (let* ([binding-info
             (map (lambda (name val)
                    (match val
                      ;; Pure lambda (lam) → direct call
                      [(lam ,p ,lbody)
                       (list name 'direct val)]
                      ;; Applicative: wrap(vau) — compiled as lambda, captures env lexically
                      [(wrap (vau ,p ,wep ,wbody ,wbta))
                       (list name 'direct val)]
                      [(wrap (vau ,p ,wep ,wbody))
                       (list name 'direct val)]
                      ;; BTA-annotated vau (genuine operative) → specialize at call sites
                      [(vau ,p ,vep ,vbody ,vbta)
                       (guard vep)
                       (list name 'vau val)]
                      ;; Vau with #f ep
                      [(vau ,p #f ,vbody)
                       (list name 'vau val)]
                      ;; Other
                      [,_ (list name 'other val)]))
                  names vals)]
            ;; Build new ctx from bindings
            [new-ctx
             (append
              (filter-map
               (lambda (info)
                 (let ([name (car info)]
                       [kind (cadr info)]
                       [val  (caddr info)])
                   (cond
                     [(eq? kind 'direct) (cons name (list 'direct val))]
                     [(eq? kind 'vau)
                      (match val
                        [(vau ,p ,vep ,vbody ,vbta)
                         (cons name `(vau-info ,p ,vep ,vbody))]
                        [(vau ,p ,vep ,vbody)
                         (cons name `(vau-info ,p ,vep ,vbody))])]
                     [else #f])))
               binding-info)
              ctx)]
            ;; Compile bindings (skip vau — they're specialized at call sites)
            [compiled-bindings
             (filter-map
              (lambda (info)
                (let ([name (car info)]
                      [kind (cadr info)]
                      [val  (caddr info)])
                  (cond
                    [(eq? kind 'vau)
                     ;; Still emit vau binding for potential runtime dispatch
                     (list name (codegen* val new-ctx))]
                    [else
                     (list name (codegen* val new-ctx))])))
              binding-info)])
       ;; Extend dynamic env with letrec bindings so that eval'd code
       ;; (via seed-eval) can reference user-defined functions.
       ;; Only do this when there are vau bindings (which implies eval usage).
       (let ([body-code (codegen* body new-ctx)]
             [has-vau (exists (lambda (info) (eq? (cadr info) 'vau)) binding-info)])
         (if has-vau
             `(letrec ,compiled-bindings
                (let ([env (list* ,@(map (lambda (n) `(cons ',n ,n)) names) env)])
                  ,body-code))
             `(letrec ,compiled-bindings
                ,body-code))))]

    ;; --- Call-site dispatch ---

    ;; Call to known direct lam → (name args...)
    [(call (var ,name local) ,args)
     (guard (let ([e (assq name ctx)]) (and e (pair? (cdr e)) (eq? (cadr e) 'direct))))
     `(,name ,@(map (lambda (a) (codegen* a ctx)) args))]

    ;; Call to known vau → SPECIALIZE at compile time
    [(call (var ,name local) ,args)
     (guard (let ([e (assq name ctx)]) (and e (vau-info? (cdr e)))))
     (let* ([info (cdr (assq name ctx))]
            [vau-params (cadr info)]
            [vau-ep (caddr info)]
            [vau-body (cadddr info)])
       (codegen* (specialize vau-body vau-params args vau-ep ctx) ctx))]

    ;; Call to free primitive → (name args...)
    [(call (var ,name free) ,args)
     (guard (memq name *primitives*))
     `(,name ,@(map (lambda (a) (codegen* a ctx)) args))]

    ;; Call to other local (e.g., lambda parameter) → (name args...)
    [(call (var ,name local) ,args)
     `(,name ,@(map (lambda (a) (codegen* a ctx)) args))]

    ;; Call to other free → (name args...)
    [(call (var ,name free) ,args)
     `(,name ,@(map (lambda (a) (codegen* a ctx)) args))]

    ;; Generic call — runtime dispatch
    [(call ,op ,args)
     (let ([op-code (codegen* op ctx)]
           [arg-codes (map (lambda (a) (codegen* a ctx)) args)]
           [syntax-args (map (lambda (a) `',(ast->src* a)) args)])
       `(let ([proc ,op-code])
          (if (and (pair? proc) (eq? (car proc) 'operative))
              ((cdr proc) env ,@syntax-args)
              (proc ,@arg-codes))))]

    ;; --- Vau/eval support ---
    [(eval ,e ,ev) `(seed-eval ,(codegen* e ctx) ,(codegen* ev ctx))]

    ;; --- Time ---
    [(time ,e) `(time ,(codegen* e ctx))]

    ;; BTA-annotated vau (5-field) with live ep
    [(vau ,p ,ep ,body ,bta)
     (guard ep)
     (let* ([all-params (param-names p)]
            [new-ctx (append (map (lambda (n) (cons n 'scheme-var)) all-params) ctx)]
            [body* (codegen* body new-ctx)])
       `(cons 'operative
              (lambda (env . ,p)
                (let ([,ep env]) ,body*))))]

    ;; Vau with #f ep (non-BTA, from wrap or bare)
    [(vau ,p ,ep ,body)
     (guard (not ep))
     (let* ([all-params (param-names p)]
            [new-ctx (append (map (lambda (n) (cons n 'scheme-var)) all-params) ctx)]
            [body* (codegen* body new-ctx)])
       `(cons 'operative (lambda (env . ,p) ,body*)))]

    ;; wrap(vau with live ep, BTA) → impure applicative
    [(wrap (vau ,p ,ep ,body ,bta))
     (guard ep)
     (let* ([all-params (param-names p)]
            [new-ctx (append (map (lambda (n) (cons n 'scheme-var)) all-params) ctx)]
            [body* (codegen* body new-ctx)])
       `(lambda ,p
          (let ([env (list* ,@(map (lambda (n) `(cons ',n ,n)) all-params)
                            env)])
            (let ([,ep env]) ,body*))))]

    ;; wrap(vau with live ep, no BTA) → impure applicative
    [(wrap (vau ,p ,ep ,body))
     (guard ep)
     (let* ([all-params (param-names p)]
            [new-ctx (append (map (lambda (n) (cons n 'scheme-var)) all-params) ctx)]
            [body* (codegen* body new-ctx)])
       `(lambda ,p
          (let ([env (list* ,@(map (lambda (n) `(cons ',n ,n)) all-params)
                            env)])
            (let ([,ep env]) ,body*))))]

    ;; wrap(vau with #f ep) that wasn't lowered to lam (has free vars)
    [(wrap (vau ,p ,ep ,body))
     (guard (not ep))
     (let* ([all-params (param-names p)]
            [new-ctx (append (map (lambda (n) (cons n 'scheme-var)) all-params) ctx)]
            [body* (codegen* body new-ctx)])
       ;; OPTIMIZATION: If body doesn't reference env, emit plain lambda
       ;; This enables Chez's escape analysis for closures with free vars
       (if (not (references-env? body))
           `(lambda ,p ,body*)  ; Pure applicative - no env construction
           `(lambda ,p          ; Needs env access - construct env
              (let ([env (list* ,@(map (lambda (n) `(cons ',n ,n)) all-params)
                                env)])
                ,body*))))]

    ;; Generic wrap
    [(wrap ,inner) (codegen* inner ctx)]

    ;; Dynamic calling environment
    [(dyn-env) 'env]

    [,x (error 'codegen "unknown form" x)]))

;; =========================================================================
;; RUNTIME
;; =========================================================================

;; env-ref: simple alist lookup
(define (env-ref name env)
  (cond [(assq name env) => cdr]
        [else (error 'env-ref "unbound" name)]))

;; env-ref with auto-unbox (for letrec boxes in interpreter)
(define (env-ref-unbox name env)
  (cond [(assq name env) =>
         (lambda (binding)
           (let ([val (cdr binding)])
             (if (box? val) (unbox val) val)))]
        [else (error 'env-ref-unbox "unbound" name)]))

;; Bind parameter tree to argument list, extending env
(define (bind-params params args env)
  (cond
    [(symbol? params) (cons (cons params args) env)]
    [(null? params) env]
    [(pair? params)
     (bind-params (cdr params) (cdr args)
                  (bind-params (car params) (car args) env))]
    [else env]))

;; Interpreter fallback for eval (vau programs)
(define (seed-eval expr env)
  (match expr
    [,s (guard (symbol? s)) (env-ref-unbox s env)]
    [,n (guard (null? n)) n]
    [(,head ,d) (guard (eq? head 'quote)) d]
    [(if ,t ,c ,a) (if (seed-eval t env) (seed-eval c env) (seed-eval a env))]
    [(eval ,e ,ev) (seed-eval (seed-eval e env) (seed-eval ev env))]
    [(begin . ,es) (fold-left (lambda (_ e) (seed-eval e env)) #f es)]
    [(let ,bindings ,body)
     (let loop ([bs bindings] [env env])
       (if (null? bs)
           (seed-eval body env)
           (let* ([b (car bs)]
                  [name (car b)]
                  [val (seed-eval (cadr b) env)])
             (loop (cdr bs) (cons (cons name val) env)))))]
    [(letrec ,bindings ,body)
     (let* ([names (map car bindings)]
            [boxes (map (lambda (_) (box #f)) bindings)]
            [env-with-boxes (fold-left (lambda (e nb)
                                         (cons (cons (car nb) (cdr nb)) e))
                                       env
                                       (map cons names boxes))])
       (for-each (lambda (b bx)
                   (set-box! bx (seed-eval (cadr b) env-with-boxes)))
                 bindings boxes)
       (seed-eval body env-with-boxes))]
    [(lambda ,params ,body)
     (if (symbol? params)
         (lambda vals
           (seed-eval body (cons (cons params vals) env)))
         (lambda vals
           (seed-eval body (bind-params params vals env))))]
    [(vau ,params ,ep ,body)
     (cons 'operative
           (if (symbol? params)
               (lambda (dyn-env . syntaxes)
                 (let* ([new-env (cons (cons params syntaxes) env)]
                        [new-env (if (or (eq? ep '_) (eq? ep '%ignore) (not ep))
                                     new-env
                                     (cons (cons ep dyn-env) new-env))])
                   (seed-eval body new-env)))
               (lambda (dyn-env . syntaxes)
                 (let* ([new-env (bind-params params syntaxes env)]
                        [new-env (if (or (eq? ep '_) (eq? ep '%ignore) (not ep))
                                     new-env
                                     (cons (cons ep dyn-env) new-env))])
                   (seed-eval body new-env)))))]
    ;; Application
    [(,op . ,args)
     (let ([proc (seed-eval op env)])
       (if (and (pair? proc) (eq? (car proc) 'operative))
           ;; Operative — pass env and unevaluated syntax
           (apply (cdr proc) env args)
           ;; Applicative — evaluate args first
           (let ([vals (map (lambda (a) (seed-eval a env)) args)])
             (apply proc vals))))]
    [,n (guard (number? n)) n]
    [,b (guard (boolean? b)) b]
    [,s (guard (string? s)) s]
    [() '()]
    [,p (guard (procedure? p)) p]
    [,x (guard (eq? x (void))) x]
    [_ (error 'seed-eval "unknown" expr)]))

;; Ground environment — alist mapping primitive names to Scheme values
(define ground-env
  `((+ . ,+) (- . ,-) (* . ,*) (/ . ,/)
    (< . ,<) (> . ,>) (= . ,=) (>= . ,>=) (<= . ,<=)
    (cons . ,cons) (car . ,car) (cdr . ,cdr)
    (caar . ,caar) (cadr . ,cadr) (cdar . ,cdar) (cddr . ,cddr)
    (list . ,list)
    (null? . ,null?) (pair? . ,pair?) (number? . ,number?) (symbol? . ,symbol?)
    (append . ,append) (reverse . ,reverse) (length . ,length)
    (memq . ,memq) (memv . ,memv) (member . ,member)
    (assq . ,assq) (assv . ,assv) (assoc . ,assoc)
    (list-ref . ,list-ref) (list-tail . ,list-tail)
    (quotient . ,quotient) (remainder . ,remainder) (modulo . ,modulo)
    (abs . ,abs)
    (not . ,not) (boolean? . ,boolean?) (procedure? . ,procedure?)
    (list? . ,list?) (zero? . ,zero?)
    (positive? . ,positive?) (negative? . ,negative?)
    (even? . ,even?) (odd? . ,odd?)
    (display . ,display) (newline . ,newline) (printf . ,printf)
    (string? . ,string?) (string-append . ,string-append)
    (string->number . ,string->number) (number->string . ,number->string)
    (eq? . ,eq?) (equal? . ,equal?)
    (map . ,map) (apply . ,apply)
    (exists . ,exists) (for-all . ,for-all)
    (error . ,error) (void . ,void)
    (getenv . ,getenv)
    (current-nanoseconds . ,(lambda ()
      (let ([t (current-time 'time-monotonic)])
        (+ (* (time-second t) 1000000000)
           (time-nanosecond t)))))
    ;; Operatives for the interpreter
    (quote . ,(cons 'operative (lambda (env x) x)))
    (if . ,(cons 'operative
                 (lambda (env test conseq . alt)
                   (if (seed-eval test env)
                       (seed-eval conseq env)
                       (if (null? alt) (void) (seed-eval (car alt) env))))))))

;; =========================================================================
;; DRIVER
;; =========================================================================

;; Full compilation pipeline: source → L4 → Scheme code
(define (compile expr)
  (codegen (bta (classify ((annotate '()) (parse expr))))))

;; Read all S-expression forms from a file
(define (read-all-forms filename)
  (call-with-input-file filename
    (lambda (port)
      (let loop ([forms '()])
        (let ([form (read port)])
          (if (eof-object? form)
              (reverse forms)
              (loop (cons form forms))))))))

;; Transform top-level (define ...) forms into a single letrec expression.
;; (define (f x) body) → binding: (f (lambda (x) body))
;; (define name val)   → binding: (name val)
;; Non-define forms at the end become the body.
(define (transform-to-letrec forms)
  (let loop ([fs forms] [bindings '()] [body-exprs '()])
    (cond
      [(null? fs)
       (let ([body (if (= (length body-exprs) 1)
                       (car body-exprs)
                       `(begin ,@body-exprs))])
         (if (null? bindings)
             body
             `(letrec ,(reverse bindings) ,body)))]
      [else
       (let ([f (car fs)])
         (match f
           ;; (define (name params...) body...)
           [(define (,name . ,params) . ,bodies)
            (let ([body (if (= (length bodies) 1)
                            (car bodies)
                            `(begin ,@bodies))])
              (loop (cdr fs)
                    (cons (list name `(lambda ,params ,body)) bindings)
                    body-exprs))]
           ;; (define name val)
           [(define ,name ,val)
            (loop (cdr fs)
                  (cons (list name val) bindings)
                  body-exprs)]
           ;; Non-define expression
           [,expr
            (loop (cdr fs) bindings (append body-exprs (list expr)))]))])))

;; Run a source expression through Seed compile + Chez JIT compile
(define (run expr)
  (let* ([code (compile expr)]
         [result (chez:compile code)])
    result))

;; Run with ground-env (for vau/eval programs)
(define (run-with-env expr)
  (let* ([code (compile expr)]
         [wrapped `(let ([env ',ground-env]) ,code)]
         [result (chez:compile wrapped)])
    result))

;; Timing helper
(define (current-nanoseconds)
  (let ([t (current-time 'time-monotonic)])
    (+ (* (time-second t) 1000000000)
       (time-nanosecond t))))

;; Run a .k file (always provides env for vau/eval support)
;; Reports compile/execute timing to stderr in seed.scm-compatible format.
(define (dump-file filename)
  (let* ([expr (transform-to-letrec (read-all-forms filename))]
         [code (compile expr)])
    (pretty-print code (current-error-port))))

(define (run-file filename)
  (collect-request-handler void)
  (time
    (let* ([expr (transform-to-letrec (read-all-forms filename))]
           [code (compile expr)]
           [wrapped `(let ([env ',ground-env]) ,code)])
      (chez:compile wrapped))))

;; ─────────────────────────────────────────────────────────────────
;;  Expander Integration for JIT Compilation
;; ─────────────────────────────────────────────────────────────────

;; Check if an expression is a Seed form that needs special handling
(define (seed-form? expr)
  (and (pair? expr)
       (or (eq? (car expr) 'vau)
           (eq? (car expr) 'wrap)
           ;; Add other Seed-specific forms as needed
           )))

;; Custom expander that chains Seed compilation with sc-expand
(define seed-expander
  (let ([original-sc-expand sc-expand])
    (lambda (expr env . rest)
      (cond
        ;; Seed form: use Seed compile to transform, then sc-expand the result
        [(seed-form? expr)
         (let ([compiled (compile expr)])
           ;; Wrap with environment binding if needed
           (let ([wrapped `(let ([env ',ground-env]) ,compiled)])
             (apply original-sc-expand wrapped env rest)))]
        ;; Regular Scheme: just sc-expand
        [else
         (apply original-sc-expand expr env rest)]))))

;; Install the Seed expander as the current expander
(define (enable-seed-expander!)
  (current-expand seed-expander))

;; Restore the original sc-expand
(define (disable-seed-expander!)
  (current-expand sc-expand))

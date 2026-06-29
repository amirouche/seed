;;; Seed3 — Nanopass compiler for a vau-based Scheme dialect
;;;
;;; Design priorities: readability, correctness, performance (in that order).
;;; No hardcoded primitives list. No pattern-specific optimizations.
;;; All vau semantics handled generically through BTA + specialization.
;;;
;;; This file is included by the (seed3) R6RS library wrapper.
;;; See /seed3.scm at the repository root.

;; =========================================================================
;; Configuration
;; =========================================================================

(define configure-development-mode
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
;; AST = (const <value>)                           ; self-evaluating literal
;;     | (var <name>)                              ; symbol reference
;;     | (quot <datum>)                            ; quoted datum
;;     | (if <AST> <AST> <AST>)                   ; conditional (always 3-arm)
;;     | (begin <AST> ...)                         ; sequencing
;;     | (let ((<name> <AST>) ...) <AST>)          ; local binding
;;     | (let <name> ((<name> <AST>) ...) <AST>)   ; named let (loop)
;;     | (letrec ((<name> <AST>) ...) <AST>)       ; recursive binding
;;     | (vau <params> <ep> <AST>)                 ; operative
;;     | (wrap <AST>)                              ; applicative wrapper
;;     | (eval <AST> <AST>)                        ; explicit evaluation
;;     | (call <AST> (<AST> ...))                  ; application
;;     | (dyn-env)                                 ; dynamic calling environment
;;     | (define <AST> <AST> <AST>)                ; inject binding into target env
;;
;; ep = #f          ; ignored (was _ or %ignore, or from lambda desugar)
;;    | <symbol>    ; live environment parameter

;; =========================================================================
;; Helpers
;; =========================================================================

;; Normalize environment parameter: _ and %ignore become #f (canonical ignored form).
(define (normalize-environment-parameter ep)
  (if (or (eq? ep '_) (eq? ep '%ignore))
      #f
      ep))

;; Combined map and filter in one pass.
(define (filter-map procedure list)
  (cond [(null? list) '()]
        [else (let ([value (procedure (car list))])
                (if value
                    (cons value (filter-map procedure (cdr list)))
                    (filter-map procedure (cdr list))))]))

;; Extract all parameter names from a parameter tree.
;; Handles: symbol (rest param), proper list (fixed), dotted list (fixed + rest).
(define (extract-parameter-names parameters)
  (cond [(symbol? parameters) (list parameters)]
        [(null? parameters) '()]
        [(pair? parameters)
         (append (extract-parameter-names (car parameters))
                 (extract-parameter-names (cdr parameters)))]
        [else '()]))

;; Transform local defines inside a begin into letrec bindings.
;; Handles both (define name val) and (define (names...) expr) forms.
;; Only triggers for 2-arg defines (local); 3-arg env-targeted defines pass through.
(define (transform-local-defines-to-letrec forms)
  (define (local-define? form)
    (and (pair? form) (eq? (car form) 'define)
         (= (length form) 3)))
  (define (wrap-letrec bindings body)
    (if (null? bindings) body
        `(letrec ,(reverse bindings) ,body)))
  (define (wrap-begin expressions)
    (if (= (length expressions) 1) (car expressions) `(begin ,@expressions)))
  (let loop ([fs forms] [bindings '()])
    (cond
      [(null? fs)
       (wrap-letrec bindings '(void))]
      [else
       (let ([form (car fs)])
         (cond
           ;; (define (names...) expr) — destructuring local define
           ;; Inside begin blocks, (define (pair) expr) is ALWAYS destructuring,
           ;; never function shorthand. Function shorthand only at top level.
           [(and (pair? form) (eq? (car form) 'define)
                 (= (length form) 3) (pair? (cadr form)))
            (let* ([names (cadr form)]
                   [expr (caddr form)]
                   [temporary (gensym "values")]
                   [rest (loop (cdr fs) '())]
                   [inner `(let ((,temporary ,expr))
                             (let ,(let idx-loop ([ns names] [i 0] [accumulator '()])
                                     (if (null? ns) (reverse accumulator)
                                         (idx-loop (cdr ns) (+ i 1)
                                           (cons (list (car ns) `(list-ref ,temporary ,i))
                                                 accumulator))))
                               ,rest))])
              (wrap-letrec bindings inner))]
           ;; (define name val) — simple local define
           [(local-define? form)
            (loop (cdr fs) (cons (list (cadr form) (caddr form)) bindings))]
           ;; Non-define expression
           [else
            (let ([rest (loop (cdr fs) '())])
              (wrap-letrec bindings
                (if (equal? rest '(void))
                    form
                    `(begin ,form ,rest))))]))])))

;; =========================================================================
;; PASS 1: parse  (Source S-expression -> L1 AST)
;; =========================================================================
;;
;; No catamorphism — input is unstructured S-expressions.
;; SRFI-241 match is used for pattern dispatch; recursion is explicit.

(define (parse expression)
  (match expression
    ;; ---- Self-evaluating literals ----
    [,n (guard (number? n))  `(const ,n)]
    [,b (guard (boolean? b)) `(const ,b)]
    [,s (guard (string? s))  `(const ,s)]
    [,n (guard (null? n))    `(const ,n)]

    ;; ---- Symbol (variable reference) ----
    [,s (guard (symbol? s))  `(var ,s)]

    ;; ---- Quote ----
    [(,head ,datum) (guard (eq? head 'quote))
     `(quot ,datum)]

    ;; ---- Conditionals ----
    [(if ,test ,consequent ,alternative)
     `(if ,(parse test) ,(parse consequent) ,(parse alternative))]
    [(if ,test ,consequent)
     `(if ,(parse test) ,(parse consequent) (const #f))]

    ;; ---- Begin ----
    ;; If begin contains local 2-arg defines, transform them to letrec.
    ;; 3-arg env-targeted defines are NOT local and pass through.
    [(begin . ,expressions)
     (if (exists (lambda (e)
                   (and (pair? e) (eq? (car e) 'define)
                        (= (length e) 3)))
                 expressions)
         (parse (transform-local-defines-to-letrec expressions))
         `(begin ,@(map parse expressions)))]

    ;; ---- Let* (desugars to nested let) ----
    [(let* () ,body)
     (parse body)]
    [(let* () . ,bodies)
     (parse `(begin ,@bodies))]
    [(let* ((,name ,value) . ,rest) . ,bodies)
     (parse `(let ((,name ,value)) (let* ,rest ,@bodies)))]

    ;; ---- Named let (desugars to letrec + immediate call) ----
    [(let ,name ,bindings ,body)
     (guard (symbol? name))
     (parse `(letrec ((,name (lambda ,(map car bindings) ,body)))
               (,name ,@(map cadr bindings))))]
    [(let ,name ,bindings . ,bodies)
     (guard (symbol? name))
     (parse `(letrec ((,name (lambda ,(map car bindings) ,@bodies)))
               (,name ,@(map cadr bindings))))]

    ;; ---- Let ----
    [(let ,bindings ,body)
     `(let ,(map (lambda (b) (list (car b) (parse (cadr b)))) bindings)
        ,(parse body))]
    [(let ,bindings . ,bodies)
     `(let ,(map (lambda (b) (list (car b) (parse (cadr b)))) bindings)
        ,(parse `(begin ,@bodies)))]

    ;; ---- Letrec ----
    [(letrec ,bindings ,body)
     `(letrec ,(map (lambda (b) (list (car b) (parse (cadr b)))) bindings)
        ,(parse body))]
    [(letrec ,bindings . ,bodies)
     `(letrec ,(map (lambda (b) (list (car b) (parse (cadr b)))) bindings)
        ,(parse `(begin ,@bodies)))]

    ;; ---- Lambda -> wrap(vau)  [THE KEY DESUGARING] ----
    [(lambda ,parameters ,body)
     `(wrap (vau ,parameters #f ,(parse body)))]
    [(lambda ,parameters . ,bodies)
     `(wrap (vau ,parameters #f ,(parse `(begin ,@bodies))))]

    ;; ---- Vau (operative — the core abstraction) ----
    [(vau ,parameters ,environment-parameter ,body)
     `(vau ,parameters ,(normalize-environment-parameter environment-parameter)
           ,(parse body))]
    [(vau ,parameters ,environment-parameter . ,bodies)
     `(vau ,parameters ,(normalize-environment-parameter environment-parameter)
           ,(parse `(begin ,@bodies)))]

    ;; ---- Define (3-arg: inject binding into target environment) ----
    [(define ,environment-name ,name ,value)
     (guard (not (pair? name)))
     `(define ,(parse environment-name) ,(parse name) ,(parse value))]

    ;; ---- Define (4-arg: destructuring into target environment) ----
    [(define ,environment-name (,names ...) ,expression)
     (let ([temporary (gensym "values")])
       (parse `(let ((,temporary ,expression))
                 (begin ,@(let loop ([ns names] [index 0] [accumulator '()])
                            (if (null? ns) (reverse accumulator)
                                (loop (cdr ns) (+ index 1)
                                  (cons `(define ,environment-name ,(car ns)
                                           (list-ref ,temporary ,index))
                                        accumulator))))))))]

    ;; ---- Eval ----
    [(eval ,expression ,environment)
     `(eval ,(parse expression) ,(parse environment))]

    ;; ---- Time ----
    [(time ,expression)
     `(time ,(parse expression))]

    ;; ---- Application (catch-all — MUST be last) ----
    [(,operator . ,arguments)
     `(call ,(parse operator) ,(map parse arguments))]

    ;; ---- Error ----
    [,x (error 'parse "unknown expression" x)]))

;; =========================================================================
;; AST -> Source (debugging / roundtrip testing)
;; =========================================================================

(define (ast-to-source ast)
  (match ast
    [(const ,value) value]
    [(var ,name) name]
    [(quot ,datum) `(quote ,datum)]
    [(if ,[test] ,[consequent] ,[alternative])
     `(if ,test ,consequent ,alternative)]
    [(begin ,[expression] ...) `(begin ,@expression)]
    [(let ((,name ,[value]) ...) ,[body]) `(let ,(map list name value) ,body)]
    [(letrec ((,name ,[value]) ...) ,[body]) `(letrec ,(map list name value) ,body)]
    [(wrap (vau ,parameters ,ep ,[body]))
     (guard (not ep))
     `(lambda ,parameters ,body)]
    [(wrap ,[inner]) `(wrap ,inner)]
    [(vau ,parameters ,ep ,[body])
     `(vau ,parameters ,(or ep '_) ,body)]
    [(define ,[environment-expression] ,[name-expression] ,[value-expression])
     `(define ,environment-expression ,name-expression ,value-expression)]
    [(eval ,[expression] ,[environment]) `(eval ,expression ,environment)]
    [(time ,[expression]) `(time ,expression)]
    [(call ,[operator] (,[argument] ...)) `(,operator ,@argument)]
    [,_ '???]))

;; =========================================================================
;; PASS 2: annotate  (L1 AST -> L2 AST)
;; =========================================================================
;;
;; Marks every (var <name>) as local or free:
;;   (var <name>)  ->  (var <name> local|free)
;;
;; Curried form: (annotate scope) returns an AST -> AST function.
;; SRFI-241 catamorphisms (,[var]) recurse with the same closed-over scope,
;; which is correct for positions where the scope doesn't change
;; (if, begin, wrap, eval, call). Binding forms (let, letrec, vau) use
;; explicit recursion because they extend the scope.

(define (annotate scope)
  (lambda (ast)
    (match ast
      ;; Leaves
      [(const ,value) `(const ,value)]
      [(var ,name)    `(var ,name ,(if (memq name scope) 'local 'free))]
      [(quot ,datum)  `(quot ,datum)]

      ;; Structural recursion via catamorphism (scope unchanged)
      [(if ,[test] ,[consequent] ,[alternative])
       `(if ,test ,consequent ,alternative)]
      [(begin ,[expression] ...)
       `(begin ,@expression)]
      [(wrap ,[inner])
       `(wrap ,inner)]
      [(define ,[environment-expression] ,[name-expression] ,[value-expression])
       `(define ,environment-expression ,name-expression ,value-expression)]
      [(eval ,[expression] ,[environment])
       `(eval ,expression ,environment)]
      [(time ,[expression])
       `(time ,expression)]
      [(call ,[operator] (,[argument] ...))
       `(call ,operator ,argument)]

      ;; Binding forms — explicit recursion (scope changes)
      [(let ((,name ,right-hand-side) ...) ,body)
       (let* ([annotated-rhs (map (annotate scope) right-hand-side)]
              [extended-scope (append name scope)])
         `(let ,(map list name annotated-rhs)
            ,((annotate extended-scope) body)))]

      [(letrec ((,name ,right-hand-side) ...) ,body)
       (let* ([extended-scope (append name scope)]
              [annotated-rhs (map (annotate extended-scope) right-hand-side)])
         `(letrec ,(map list name annotated-rhs)
            ,((annotate extended-scope) body)))]

      ;; vau — parameters + environment-parameter (if live) extend scope for body
      [(vau ,parameters ,environment-parameter ,body)
       (let* ([parameter-symbols (extract-parameter-names parameters)]
              [environment-symbols (if environment-parameter
                                       (list environment-parameter)
                                       '())]
              [extended-scope (append parameter-symbols environment-symbols scope)])
         `(vau ,parameters ,environment-parameter
               ,((annotate extended-scope) body)))]

      [,x (error 'annotate "unknown form" x)])))

;; =========================================================================
;; PASS 3: classify  (L2 AST -> L3 AST)
;; =========================================================================
;;
;; Lowers (wrap (vau parameters #f body)) -> (lam parameters body)
;; when body is a pure applicative: no eval nodes, no free variables.
;; Genuine operatives (live environment-parameter or eval in body)
;; stay as (vau ...).
;;
;; New L3 node:
;;   (lam <params> <AST>)   ; pure lambda (no environment, no operative tag)
;;
;; Note: there is no hardcoded primitives list. A free variable reference
;; to a standard name like + prevents lowering to lam. The codegen pass
;; handles these cases: wrap(vau) with no env reference emits a plain lambda.

;; Does the AST contain any (eval ...) node?
(define (ast-uses-eval? ast)
  (match ast
    [(eval ,_ ,_) #t]
    [(const ,_) #f]
    [(var ,_ ,_) #f]
    [(quot ,_) #f]
    [(if ,[test] ,[consequent] ,[alternative]) (or test consequent alternative)]
    [(begin ,[expression] ...) (ormap values expression)]
    [(wrap ,[inner]) inner]
    [(define ,[e] ,[n] ,[v]) (or e n v)]
    [(call ,[operator] (,[argument] ...)) (or operator (ormap values argument))]
    [(let ((,_ ,[value]) ...) ,[body]) (or (ormap values value) body)]
    [(letrec ((,_ ,[value]) ...) ,[body]) (or (ormap values value) body)]
    [(vau ,_ ,_ ,[body]) body]
    [,_ #f]))

;; Does the AST contain any (var name free) reference?
(define (ast-has-free-variables? ast)
  (match ast
    [(var ,_ free) #t]
    [(var ,_ ,_) #f]
    [(const ,_) #f]
    [(quot ,_) #f]
    [(if ,[test] ,[consequent] ,[alternative]) (or test consequent alternative)]
    [(begin ,[expression] ...) (ormap values expression)]
    [(wrap ,[inner]) inner]
    [(define ,[e] ,[n] ,[v]) (or e n v)]
    [(eval ,[expression] ,[environment]) (or expression environment)]
    [(call ,[operator] (,[argument] ...)) (or operator (ormap values argument))]
    [(let ((,_ ,[value]) ...) ,[body]) (or (ormap values value) body)]
    [(letrec ((,_ ,[value]) ...) ,[body]) (or (ormap values value) body)]
    [(vau ,_ ,_ ,[body]) body]
    [,_ #f]))

;; Does the AST reference the dynamic environment?
(define (ast-references-environment? ast)
  (match ast
    [(dyn-env) #t]
    [(eval ,_ ,_) #t]
    [(const ,_) #f]
    [(var ,_ ,_) #f]
    [(quot ,_) #f]
    [(if ,[test] ,[consequent] ,[alternative]) (or test consequent alternative)]
    [(begin ,[expression] ...) (ormap values expression)]
    [(wrap ,[inner]) inner]
    [(lam ,_ ,[body]) body]
    [(vau ,_ ,_ ,[body]) body]
    [(vau ,_ ,_ ,[body] ,_) body]
    [(define ,[e] ,[n] ,[v]) (or e n v)]
    [(time ,[expression]) expression]
    [(call ,[operator] (,[argument] ...)) (or operator (ormap values argument))]
    [(let ((,_ ,[value]) ...) ,[body]) (or (ormap values value) body)]
    [(letrec ((,_ ,[value]) ...) ,[body]) (or (ormap values value) body)]
    [,_ #f]))

;; Collect all free variable names referenced in the AST.
(define (ast-collect-free-variables ast)
  (match ast
    [(var ,name free) (list name)]
    [(var ,_ ,_) '()]
    [(const ,_) '()]
    [(quot ,_) '()]
    [(dyn-env) '()]
    [(if ,[test] ,[consequent] ,[alternative])
     (append test consequent alternative)]
    [(begin ,[expression] ...) (apply append expression)]
    [(define ,[e] ,[n] ,[v]) (append e n v)]
    [(eval ,[expression] ,[environment]) (append expression environment)]
    [(time ,[expression]) expression]
    [(call ,[operator] (,[argument] ...))
     (apply append (cons operator argument))]
    [(let ((,_ ,[value]) ...) ,[body])
     (apply append (append value (list body)))]
    [(letrec ((,_ ,[value]) ...) ,[body])
     (apply append (append value (list body)))]
    [(lam ,_ ,[body]) body]
    [(wrap ,[inner]) inner]
    [(vau ,_ ,_ ,[body]) body]
    [,_ '()]))

;; Does the AST contain any (define ...) node?
(define (ast-has-define? ast)
  (match ast
    [(define ,_ ,_ ,_) #t]
    [(const ,_) #f]
    [(var ,_ ,_) #f]
    [(var ,_) #f]
    [(quot ,_) #f]
    [(dyn-env) #f]
    [(if ,[test] ,[consequent] ,[alternative]) (or test consequent alternative)]
    [(begin ,[expression] ...) (ormap values expression)]
    [(eval ,[expression] ,[environment]) (or expression environment)]
    [(time ,[expression]) expression]
    [(call ,[operator] (,[argument] ...)) (or operator (ormap values argument))]
    [(let ((,_ ,[value]) ...) ,[body]) (or (ormap values value) body)]
    [(letrec ((,_ ,[value]) ...) ,[body]) (or (ormap values value) body)]
    [(lam ,_ ,[body]) body]
    [(wrap ,[inner]) inner]
    [(vau ,_ ,_ ,[body]) body]
    [(vau ,_ ,_ ,[body] ,_) body]
    [,_ #f]))

;; Does the AST contain a call to a free variable not in context?
;; Such calls may target operatives at runtime, making compile-time
;; specialization unsafe (syntax arguments get mangled by substitution).
(define (ast-has-unknown-operative-calls? ast context)
  (match ast
    [(call (var ,name free) ,arguments)
     (or (not (assq name context))
         (ormap (lambda (a) (ast-has-unknown-operative-calls? a context)) arguments))]
    [(call ,operator ,arguments)
     (or (ast-has-unknown-operative-calls? operator context)
         (ormap (lambda (a) (ast-has-unknown-operative-calls? a context)) arguments))]
    [(var ,_ ,_) #f]
    [(const ,_) #f]
    [(quot ,_) #f]
    [(dyn-env) #f]
    [(if ,test ,consequent ,alternative)
     (or (ast-has-unknown-operative-calls? test context)
         (ast-has-unknown-operative-calls? consequent context)
         (ast-has-unknown-operative-calls? alternative context))]
    [(begin ,expressions ...)
     (ormap (lambda (e) (ast-has-unknown-operative-calls? e context)) expressions)]
    [(define ,e ,n ,v)
     (or (ast-has-unknown-operative-calls? e context)
         (ast-has-unknown-operative-calls? n context)
         (ast-has-unknown-operative-calls? v context))]
    [(eval ,expression ,environment)
     (or (ast-has-unknown-operative-calls? expression context)
         (ast-has-unknown-operative-calls? environment context))]
    [(time ,expression) (ast-has-unknown-operative-calls? expression context)]
    [(let ((,_ ,values) ...) ,body)
     (or (ormap (lambda (v) (ast-has-unknown-operative-calls? v context)) values)
         (ast-has-unknown-operative-calls? body context))]
    [(letrec ((,_ ,values) ...) ,body)
     (or (ormap (lambda (v) (ast-has-unknown-operative-calls? v context)) values)
         (ast-has-unknown-operative-calls? body context))]
    [(lam ,_ ,body) (ast-has-unknown-operative-calls? body context)]
    [(wrap ,inner) (ast-has-unknown-operative-calls? inner context)]
    [(vau ,_ ,_ ,body) (ast-has-unknown-operative-calls? body context)]
    [,_ #f]))

;; The classify pass itself.
(define (classify ast)
  (match ast
    ;; THE KEY RULE: wrap(vau with #f ep) -> lam when pure
    [(wrap (vau ,parameters ,ep ,body))
     (guard (not ep))
     (let ([classified-body (classify body)])
       (if (and (not (ast-uses-eval? classified-body))
                (not (ast-has-free-variables? classified-body)))
           `(lam ,parameters ,classified-body)
           `(wrap (vau ,parameters #f ,classified-body))))]

    ;; Bare vau with live environment-parameter — genuine operative
    [(vau ,parameters ,environment-parameter ,[body])
     `(vau ,parameters ,environment-parameter ,body)]

    ;; All other nodes — pure catamorphism
    [(const ,value) `(const ,value)]
    [(var ,name ,binding) `(var ,name ,binding)]
    [(quot ,datum) `(quot ,datum)]
    [(if ,[test] ,[consequent] ,[alternative])
     `(if ,test ,consequent ,alternative)]
    [(begin ,[expression] ...) `(begin ,@expression)]
    [(define ,[e] ,[n] ,[v]) `(define ,e ,n ,v)]
    [(eval ,[expression] ,[environment]) `(eval ,expression ,environment)]
    [(time ,[expression]) `(time ,expression)]
    [(call ,[operator] (,[argument] ...)) `(call ,operator ,argument)]
    [(let ((,name ,[value]) ...) ,[body])
     `(let ,(map list name value) ,body)]
    [(letrec ((,name ,[value]) ...) ,[body])
     `(letrec ,(map list name value) ,body)]
    [,x (error 'classify "unknown form" x)]))

;; =========================================================================
;; PASS 4: analyze-binding-time  (L3 AST -> L4 AST)
;; =========================================================================
;;
;; Annotates each parameter of genuine operatives (vau with live ep)
;; with its binding-time classification:
;;   static-eval   — parameter only appears in (eval param ep) patterns
;;   static-syntax — parameter is used as unevaluated syntax (or unused)
;;   dynamic       — parameter used in both eval and non-eval positions
;;
;; L4 AST change:
;;   (vau <params> <ep> <AST> <binding-times>)
;;   where binding-times = ((name classification) ...)

;; Collect parameter names appearing in (eval (var name local) (var ep local))
(define (collect-direct-eval-parameters ep-name parameter-set body)
  (define (walk ast)
    (match ast
      [(eval (var ,name local) (var ,ep local))
       (guard (and (eq? ep ep-name) (memq name parameter-set)))
       (list name)]
      [(const ,_) '()]
      [(var ,_ ,_) '()]
      [(quot ,_) '()]
      [(if ,[test] ,[consequent] ,[alternative])
       (append test consequent alternative)]
      [(begin ,[expression] ...) (apply append expression)]
      [(define ,[e] ,[n] ,[v]) (append e n v)]
      [(eval ,[expression] ,[environment]) (append expression environment)]
      [(time ,[expression]) expression]
      [(call ,[operator] (,[argument] ...))
       (apply append (cons operator argument))]
      [(let ((,_ ,[value]) ...) ,[body])
       (apply append (append value (list body)))]
      [(letrec ((,_ ,[value]) ...) ,[body])
       (apply append (append value (list body)))]
      [(lam ,_ ,[body]) body]
      [(wrap ,[inner]) inner]
      [(vau ,_ ,_ ,[body]) body]
      [,_ '()]))
  (walk body))

;; Collect parameter names appearing as (var name local) OUTSIDE eval patterns.
(define (collect-bare-variable-uses ep-name parameter-set body)
  (define (walk ast)
    (match ast
      ;; Direct eval of parameter — skip this entire node
      [(eval (var ,name local) (var ,ep local))
       (guard (and (eq? ep ep-name) (memq name parameter-set)))
       '()]
      ;; Parameter variable — count it
      [(var ,name local)
       (guard (memq name parameter-set))
       (list name)]
      [(const ,_) '()]
      [(var ,_ ,_) '()]
      [(quot ,_) '()]
      [(if ,[test] ,[consequent] ,[alternative])
       (append test consequent alternative)]
      [(begin ,[expression] ...) (apply append expression)]
      [(define ,[e] ,[n] ,[v]) (append e n v)]
      [(eval ,[expression] ,[environment]) (append expression environment)]
      [(time ,[expression]) expression]
      [(call ,[operator] (,[argument] ...))
       (apply append (cons operator argument))]
      [(let ((,_ ,[value]) ...) ,[body])
       (apply append (append value (list body)))]
      [(letrec ((,_ ,[value]) ...) ,[body])
       (apply append (append value (list body)))]
      [(lam ,_ ,[body]) body]
      [(wrap ,[inner]) inner]
      [(vau ,_ ,_ ,[body]) body]
      [,_ '()]))
  (walk body))

;; Classify each parameter's binding time.
(define (compute-parameter-binding-times parameters environment-parameter body)
  (let* ([names (extract-parameter-names parameters)]
         [eval-set (collect-direct-eval-parameters
                     environment-parameter names body)]
         [bare-set (collect-bare-variable-uses
                     environment-parameter names body)])
    (map (lambda (name)
           (list name (cond
                        [(and (memq name eval-set) (memq name bare-set)) 'dynamic]
                        [(memq name eval-set) 'static-eval]
                        [else 'static-syntax])))
         names)))

;; The binding-time analysis pass.
(define (analyze-binding-time ast)
  (match ast
    ;; Genuine vau with live environment-parameter — analyze then recurse
    [(vau ,parameters ,environment-parameter ,body)
     (guard environment-parameter)
     (let* ([binding-times (compute-parameter-binding-times
                             parameters environment-parameter body)]
            [analyzed-body (analyze-binding-time body)])
       `(vau ,parameters ,environment-parameter ,analyzed-body ,binding-times))]

    ;; Vau with #f environment-parameter — just recurse
    [(vau ,parameters ,ep ,[body])
     (guard (not ep))
     `(vau ,parameters ,ep ,body)]

    ;; All other nodes — pure catamorphism
    [(const ,value) `(const ,value)]
    [(var ,name ,binding) `(var ,name ,binding)]
    [(quot ,datum) `(quot ,datum)]
    [(if ,[test] ,[consequent] ,[alternative])
     `(if ,test ,consequent ,alternative)]
    [(begin ,[expression] ...) `(begin ,@expression)]
    [(define ,[e] ,[n] ,[v]) `(define ,e ,n ,v)]
    [(eval ,[expression] ,[environment]) `(eval ,expression ,environment)]
    [(time ,[expression]) `(time ,expression)]
    [(call ,[operator] (,[argument] ...)) `(call ,operator ,argument)]
    [(lam ,parameters ,[body]) `(lam ,parameters ,body)]
    [(wrap ,[inner]) `(wrap ,inner)]
    [(let ((,name ,[value]) ...) ,[body])
     `(let ,(map list name value) ,body)]
    [(letrec ((,name ,[value]) ...) ,[body])
     `(letrec ,(map list name value) ,body)]
    [,x (error 'analyze-binding-time "unknown form" x)]))

;; =========================================================================
;; PASS 5: generate-code  (L4 AST -> Chez Scheme S-expression)
;; =========================================================================
;;
;; Context-aware code generation with call-site specialization for vau.
;;
;; context = alist of (name . info)
;;   info = 'direct                     — pure lam, call as (name args...)
;;        | (vau-info params ep body)   — operative, specialize at call sites
;;        | 'scheme-variable            — lambda-bound Chez variable
;;        | '(%has-environment . #t)    — inside a vau body with live ep
;;        | '(%has-news . #t)           — inside a vau body that uses define

;; Is this a vau-info context entry?
(define (vau-info? info)
  (and (pair? info) (eq? (car info) 'vau-info)))

;; Recover source S-expression from L4 AST (for quoting syntax in specialization)
(define (ast-to-source-form ast)
  (match ast
    [(const ,value) value]
    [(var ,name ,_) name]
    [(var ,name) name]
    [(quot ,datum) `(quote ,datum)]
    [(if ,test ,consequent ,alternative)
     `(if ,(ast-to-source-form test)
          ,(ast-to-source-form consequent)
          ,(ast-to-source-form alternative))]
    [(begin ,expressions ...)
     `(begin ,@(map ast-to-source-form expressions))]
    [(let ((,name ,value) ...) ,body)
     `(let ,(map (lambda (n v) (list n (ast-to-source-form v))) name value)
        ,(ast-to-source-form body))]
    [(letrec ((,name ,value) ...) ,body)
     `(letrec ,(map (lambda (n v) (list n (ast-to-source-form v))) name value)
        ,(ast-to-source-form body))]
    [(lam ,parameters ,body) `(lambda ,parameters ,(ast-to-source-form body))]
    [(wrap (vau ,parameters #f ,body))
     `(lambda ,parameters ,(ast-to-source-form body))]
    [(wrap (vau ,parameters #f ,body ,_))
     `(lambda ,parameters ,(ast-to-source-form body))]
    [(wrap ,inner) `(wrap ,(ast-to-source-form inner))]
    [(vau ,parameters ,ep ,body ,_)
     `(vau ,parameters ,(or ep '_) ,(ast-to-source-form body))]
    [(vau ,parameters ,ep ,body)
     `(vau ,parameters ,(or ep '_) ,(ast-to-source-form body))]
    [(define ,e ,n ,v)
     `(define ,(ast-to-source-form e) ,(ast-to-source-form n)
              ,(ast-to-source-form v))]
    [(eval ,expression ,environment)
     `(eval ,(ast-to-source-form expression) ,(ast-to-source-form environment))]
    [(time ,expression) `(time ,(ast-to-source-form expression))]
    [(call ,operator ,arguments)
     `(,(ast-to-source-form operator) ,@(map ast-to-source-form arguments))]
    [(dyn-env) 'env]
    [,_ '???]))

;; -------------------------------------------------------------------------
;; Specialization: partial evaluation of vau bodies at compile time
;; -------------------------------------------------------------------------
;;
;; Core of the first Futamura projection for vau macros.

;; Bind vau parameters to arguments for substitution.
;; Returns alist of (parameter-name . argument-ast).
(define (bind-parameters-to-arguments parameters arguments)
  (cond
    [(null? parameters) '()]
    [(symbol? parameters)
     ;; Rest parameter — collect remaining arguments as a quoted source list
     (list (cons parameters `(quot ,(map ast-to-source-form arguments))))]
    [(pair? parameters)
     (cons (cons (car parameters) (car arguments))
           (bind-parameters-to-arguments (cdr parameters) (cdr arguments)))]))

;; Extract free symbols from an S-expression (for environment extension).
(define (extract-free-symbols s-expression)
  (cond
    [(symbol? s-expression)
     (if (memq s-expression '(quote if let letrec lambda begin define vau wrap eval
                              guard and or cond else not))
         '() (list s-expression))]
    [(pair? s-expression)
     (cond
       [(eq? (car s-expression) 'quote) '()]
       [(eq? (car s-expression) 'lambda)
        (let ([parameters (cadr s-expression)]
              [body (cddr s-expression)])
          (let ([parameter-names
                  (let loop ([p parameters])
                    (cond [(null? p) '()]
                          [(symbol? p) (list p)]
                          [(pair? p) (cons (car p) (loop (cdr p)))]
                          [else '()]))])
            (filter (lambda (s) (not (memq s parameter-names)))
                    (extract-free-symbols body))))]
       [(memq (car s-expression) '(let letrec))
        (let ([bindings (cadr s-expression)]
              [body (cddr s-expression)])
          (if (and (pair? bindings) (pair? (car bindings)))
              (let ([names (map car bindings)]
                    [value-symbols (extract-free-symbols (map cadr bindings))]
                    [body-symbols (extract-free-symbols body)])
                (append value-symbols
                        (filter (lambda (s)
                                  (and (not (memq s value-symbols))
                                       (not (memq s names))))
                                body-symbols)))
              (let ([left (extract-free-symbols (car s-expression))]
                    [right (extract-free-symbols (cdr s-expression))])
                (append left (filter (lambda (s) (not (memq s left))) right)))))]
       [else
        (let ([left (extract-free-symbols (car s-expression))]
              [right (extract-free-symbols (cdr s-expression))])
          (append left (filter (lambda (s) (not (memq s left))) right)))])]
    [else '()]))

;; Build environment extension for operative dispatch: capture Chez locals
;; that appear free in syntax-arguments so seed-evaluate can resolve them.
;; Is this AST node a compile-time-known value?
(define (static-value? ast)
  (match ast
    [(const ,_) #t]
    [(quot ,_) #t]
    [,_ #f]))

;; Extract the runtime value from a static AST node
(define (static-value-extract ast)
  (match ast
    [(const ,value) value]
    [(quot ,datum) datum]))

;; Wrap a runtime value back into the appropriate AST node
(define (value-to-ast value)
  (if (or (number? value) (boolean? value) (string? value) (null? value))
      `(const ,value)
      `(quot ,value)))

;; Primitives safe to fold at compile time
(define *foldable-primitives*
  '(car cdr caar cadr cdar cddr caaar caadr
    cons list append reverse length
    null? pair? number? symbol? boolean? string? eq? equal? not
    + - * quotient remainder modulo abs
    = < > <= >=))

;; Try to fold (name arg1 arg2 ...) at compile time.
;; Returns AST node or #f.
(define (try-fold-call name arg-asts)
  (and (memq name *foldable-primitives*)
       (for-all static-value? arg-asts)
       (let ([values (map static-value-extract arg-asts)])
         (call/cc (lambda (escape)
           (with-exception-handler
             (lambda (condition) (escape #f))
             (lambda ()
               (value-to-ast (apply (eval name) values)))))))))

;; Inline a known lambda at a call site when some arguments are static.
;; Static arguments are folded into the substitution; dynamic arguments
;; become let bindings. Returns the specialized body or #f on failure.
(define (inline-lambda lam-ast arg-asts substitution environment-parameter
                       context lambda-environment inline-fuel)
  (match lam-ast
    [(lam ,parameters ,body)
     (guard (list? parameters) (= (length parameters) (length arg-asts)))
     (let ([clean-substitution
             (remp (lambda (s) (memq (car s) parameters)) substitution)])
       (let loop ([ps parameters] [as arg-asts]
                  [new-substitution clean-substitution] [kept '()])
         (if (null? ps)
             (let ([body-result
                     (specialize-expression body new-substitution
                       environment-parameter context lambda-environment
                       inline-fuel)])
               (if (null? kept) body-result `(let ,(reverse kept) ,body-result)))
             (if (static-value? (car as))
                 (loop (cdr ps) (cdr as)
                       (cons (cons (car ps) (car as)) new-substitution) kept)
                 (loop (cdr ps) (cdr as) new-substitution
                       (cons (list (car ps) (car as)) kept))))))]
    [,_ #f]))

(define (build-operative-environment-extension syntax-arguments context)
  (let* ([source-forms (map (lambda (sa)
                              (if (and (pair? sa) (eq? (car sa) 'quote))
                                  (cadr sa)
                                  sa))
                            syntax-arguments)]
         [all-symbols (apply append (map extract-free-symbols source-forms))]
         [unique (let loop ([symbols all-symbols] [seen '()])
                   (cond [(null? symbols) (reverse seen)]
                         [(memq (car symbols) seen) (loop (cdr symbols) seen)]
                         [else (loop (cdr symbols) (cons (car symbols) seen))]))]
         ;; Keep symbols that are Chez locals from context
         [chez-locals (filter (lambda (s)
                                (or (assq s context)
                                    (and (eq? s 'env)
                                         (assq '%has-environment context))))
                              unique)])
    chez-locals))

;; Wrap an operative call body with environment extension if needed.
(define (wrap-operative-call-with-environment locals call-code)
  (if (null? locals)
      call-code
      `(let ([env (list* ,@(map (lambda (s) `(cons ',s ,s)) locals) env)])
         ,call-code)))

;; Is NAME a host (Chez) top-level binding?  Used to resolve free variables in
;; an eval'd body directly to the host global (native speed) instead of walking
;; the runtime environment alist on every node.  This replaces seed/seed2's
;; hardcoded *primitives* list with host introspection, so no list is baked in.
(define (host-global? name)
  (top-level-bound? name))

;; Compile an eval'd body expression inline instead of falling back to
;; seed-evaluate. Takes the body S-expression and a bindings AST (the alist
;; of pattern bindings from pmatch). Resolves each free variable to one of:
;;   - a Chez local already in context           -> bare reference
;;   - a host global (apply, +, quotient, ...)   -> bare reference (native)
;;   - a pattern variable / dynamic global       -> safe lookup:
;;        (let ((%b (assq 'sym binds)))
;;          (if %b (cdr %b) (eval 'sym env)))
;; The safe lookup tries the pmatch binds alist first (pattern vars; alist
;; fusion collapses this to a direct local), and falls back to env lookup for
;; genuinely dynamic globals.  Host globals skip binds entirely — that is what
;; closes the per-node env-walk perf gap on multi-operand ellipsis bodies.
(define (compile-eval-body body-sexp binds-ast env-ast context
                           lambda-environment inline-fuel)
  (let* ([all-vars (extract-free-symbols body-sexp)]
         [scope (map (lambda (v) (cons v 'local)) all-vars)]
         [parsed (parse body-sexp)]
         [annotated ((annotate scope) parsed)]
         [body-ast (specialize-expression annotated '() #f context
                                          lambda-environment inline-fuel)]
         ;; After specialization, only generate env-lookups for variables
         ;; that are still referenced.
         [body-free (ast-collect-free-variables body-ast)]
         [live-vars (filter (lambda (v) (memq v body-free)) all-vars)]
         ;; Variables already in context (Chez locals) and host globals both
         ;; resolve directly as bare references — no binds lookup needed.
         ;; Only pattern vars / dynamic globals need the safe lookup.
         [need-lookup (filter (lambda (v)
                                (not (or (assq v context) (host-global? v))))
                              live-vars)]
         ;; For each remaining variable: try assq from binds (pattern vars),
         ;; fall back to env lookup (dynamic globals).  Each %b is scoped to its
         ;; own inner let so the name can be reused safely.
         [let-binds (map (lambda (v)
                           (list v
                                 `(let ([%b (call (var assq free)
                                              ((quot ,v) ,binds-ast))])
                                    (if (var %b local)
                                        (call (var cdr free) ((var %b local)))
                                        (eval (quot ,v) ,env-ast)))))
                         need-lookup)])
    (if (null? let-binds) body-ast `(let ,let-binds ,body-ast))))

;; Top-level specialization: bind parameters, run spec, iterate to fixpoint.
(define (specialize body parameters arguments environment-parameter context)
  (let* ([substitution (bind-parameters-to-arguments parameters arguments)]
         [lambda-environment
           (filter-map
             (lambda (entry)
               (and (pair? (cdr entry))
                    (eq? (cadr entry) 'direct)
                    (let ([ast (caddr entry)])
                      (match ast
                        [(lam ,p ,b) (cons (car entry) ast)]
                        [(wrap (vau ,p #f ,b)) (cons (car entry) `(lam ,p ,b))]
                        [(wrap (vau ,p #f ,b ,_)) (cons (car entry) `(lam ,p ,b))]
                        [,_ #f]))))
             context)]
         [ast (specialize-expression body substitution environment-parameter
                                     context lambda-environment 100)])
    ;; Iterate with empty substitution + alist fusion until fixed point
    (let loop ([ast ast] [fuel 10])
      (if (zero? fuel) ast
          (let* ([ast-prime (specialize-expression ast '() #f context
                                                   lambda-environment 100)]
                 [ast-fused (fuse-alist-lets ast-prime)])
            (if (equal? ast-fused ast) ast
                (loop ast-fused (- fuel 1))))))))

;; Core specialization: transform AST by applying substitutions.
(define (specialize-expression ast substitution environment-parameter
                               context lambda-environment inline-fuel)
  (match ast
    ;; Constants — pass through
    [(const ,value) ast]
    [(quot ,datum) ast]
    [(dyn-env) ast]

    ;; Local variable
    [(var ,name local)
     (cond
       ;; Parameter in substitution -> quote the syntax
       [(assq name substitution)
        => (lambda (entry)
             (let ([value (cdr entry)])
               (cond
                 ;; Copy-propagation alias
                 [(and (pair? value) (eq? (car value) 'alias))
                  (cadr value)]
                 ;; Already quoted
                 [(and (pair? value) (eq? (car value) 'quot))
                  value]
                 ;; Vau operand: quote it
                 [else
                  `(quot ,(ast-to-source-form value))])))]
       ;; Environment parameter -> dynamic environment
       [(eq? name environment-parameter) '(dyn-env)]
       ;; Other local -> keep as-is
       [else ast])]

    ;; Free variable — pass through
    [(var ,name free) ast]

    ;; Static eval: (eval param-ref ep-ref) -> compile argument directly
    [(eval (var ,name local) (var ,ep local))
     (guard (eq? ep environment-parameter))
     (let ([entry (assq name substitution)])
       (if entry
           (let ([value (cdr entry)])
             (if (and (pair? value) (eq? (car value) 'alias))
                 (cadr value) value))
           `(eval (var ,name local) (dyn-env))))]

    ;; General eval with environment-parameter -> spec the expression
    [(eval ,expression (var ,ep local))
     (guard (eq? ep environment-parameter))
     (let ([specialized (specialize-expression expression substitution
                          environment-parameter context '() inline-fuel)])
       ;; If the result is a static quoted call to a known vau, specialize it
       (if (and (> inline-fuel 0)
                (pair? specialized) (eq? (car specialized) 'quot)
                (pair? (cadr specialized))
                (symbol? (car (cadr specialized)))
                (assq (car (cadr specialized)) context))
           (let* ([form (cadr specialized)]
                  [entry (assq (car form) context)])
             (if (vau-info? (cdr entry))
                 (let* ([info (cdr entry)]
                        [vau-parameters (cadr info)]
                        [vau-ep (caddr info)]
                        [vau-body (cadddr info)]
                        [argument-asts
                          (map (lambda (f) ((annotate '()) (parse f)))
                               (cdr form))])
                   (specialize vau-body vau-parameters argument-asts vau-ep context))
                 `(eval ,specialized (dyn-env))))
           `(eval ,specialized (dyn-env))))]

    ;; Eval of make-let with static body -> compile directly
    ;; Detects (eval (make-let binds (quot body)) env) and compiles the body
    ;; inline with assq lookups for bindings, which alist fusion then eliminates.
    ;; make-let may be local or free depending on scope.
    [(eval (call (var ,ml ,_) (,binds-ast (quot ,body-sexp))) (dyn-env))
     (guard (eq? ml 'make-let))
     (let ([binds-specialized (specialize-expression binds-ast substitution
                                environment-parameter context
                                lambda-environment inline-fuel)])
       (compile-eval-body body-sexp binds-specialized '(dyn-env) context
                          lambda-environment inline-fuel))]

    ;; Eval of static quoted vau call -> specialize directly
    [(eval (quot ,form) (dyn-env))
     (guard (and (> inline-fuel 0)
                 (pair? form) (symbol? (car form))
                 (let ([e (assq (car form) context)])
                   (and e (vau-info? (cdr e))))))
     (let* ([vau-name (car form)]
            [source-arguments (cdr form)]
            [info (cdr (assq vau-name context))]
            [vau-parameters (cadr info)]
            [vau-ep (caddr info)]
            [vau-body (cadddr info)]
            [argument-asts
              (map (lambda (f) ((annotate '()) (parse f)))
                   source-arguments)])
       (specialize vau-body vau-parameters argument-asts vau-ep context))]

    ;; Eval with different environment — specialize expression
    [(eval ,expression ,environment-expression)
     `(eval ,(specialize-expression expression substitution environment-parameter
                                     context '() inline-fuel)
            ,(specialize-expression environment-expression substitution
                                     environment-parameter context
                                     lambda-environment inline-fuel))]

    ;; If — specialize + fold constant tests
    [(if ,test ,consequent ,alternative)
     (let ([specialized-test
             (specialize-expression test substitution environment-parameter
                                    context lambda-environment inline-fuel)])
       (cond
         ;; Constant true -> select consequent
         [(and (pair? specialized-test) (eq? (car specialized-test) 'const)
               (cadr specialized-test))
          (specialize-expression consequent substitution environment-parameter
                                 context lambda-environment inline-fuel)]
         ;; Constant false -> select alternative
         [(and (pair? specialized-test) (eq? (car specialized-test) 'const)
               (not (cadr specialized-test)))
          (specialize-expression alternative substitution environment-parameter
                                 context lambda-environment inline-fuel)]
         ;; Dynamic -> keep if
         [else
          `(if ,specialized-test
               ,(specialize-expression consequent substitution environment-parameter
                                        context lambda-environment inline-fuel)
               ,(specialize-expression alternative substitution environment-parameter
                                        context lambda-environment inline-fuel))]))]

    ;; Begin — specialize + collapse
    [(begin ,expressions ...)
     (let ([specialized (map (lambda (e)
                               (specialize-expression e substitution
                                 environment-parameter context
                                 lambda-environment inline-fuel))
                             expressions)])
       (if (= (length specialized) 1)
           (car specialized)
           `(begin ,@specialized)))]

    ;; Let — specialize + propagate static bindings
    [(let ((,names ,values) ...) ,body)
     (let loop ([ns names] [vs values] [sub substitution] [kept '()])
       (if (null? ns)
           (let* ([kept-names (map car kept)]
                  [body-sub (if (null? kept-names) sub
                                (remp (lambda (s) (memq (car s) kept-names)) sub))]
                  [body-context (append
                                  (map (lambda (n) (cons n 'scheme-variable)) kept-names)
                                  context)]
                  [specialized-body
                    (specialize-expression body body-sub environment-parameter
                                           body-context lambda-environment inline-fuel)])
             (if (null? kept)
                 specialized-body
                 `(let ,(reverse kept) ,specialized-body)))
           (let ([specialized-value
                   (specialize-expression (car vs) sub environment-parameter
                                          context lambda-environment inline-fuel)])
             (if (and (pair? specialized-value)
                      (memq (car specialized-value) '(const quot)))
                 ;; Static -> fold into substitution, drop binding
                 (loop (cdr ns) (cdr vs)
                       (cons (cons (car ns) specialized-value) sub) kept)
                 ;; Dynamic -> copy-propagate local variable aliases
                 (if (and (pair? specialized-value)
                          (eq? (car specialized-value) 'var)
                          (pair? (cdr specialized-value))
                          (pair? (cddr specialized-value))
                          (eq? (caddr specialized-value) 'local))
                     (loop (cdr ns) (cdr vs)
                           (cons (cons (car ns) (list 'alias specialized-value)) sub)
                           kept)
                     (loop (cdr ns) (cdr vs) sub
                           (cons (list (car ns) specialized-value) kept)))))))]

    ;; Call to free — specialize arguments + constant fold + inline from lenv
    [(call (var ,name free) ,arguments)
     (let ([arg-asts (map (lambda (a)
                            (specialize-expression a substitution environment-parameter
                                                   context lambda-environment inline-fuel))
                          arguments)])
       (or (try-fold-call name arg-asts)
           ;; Inline known lambda from lambda-environment (same as local calls)
           (and (> inline-fuel 0)
                (assq name lambda-environment)
                (exists (lambda (a)
                          (and (static-value? a)
                               (not (equal? a '(quot ())))))
                        arg-asts)
                (let* ([lam-ast (cdr (assq name lambda-environment))]
                       [result (inline-lambda lam-ast arg-asts
                                 substitution environment-parameter context
                                 lambda-environment (- inline-fuel 1))])
                  (and result
                       (not (match lam-ast
                              [(lam ,parameters ,_)
                               (let ([free-in-result
                                       (ast-collect-free-variables result)])
                                 (exists (lambda (p) (memq p free-in-result))
                                         parameters))]
                              [,_ #f]))
                       result)))
           `(call (var ,name free) ,arg-asts)))]

    ;; Call to known vau in context -> specialize at specialization time
    [(call (var ,name local) ,arguments)
     (guard (and (> inline-fuel 0)
                 (not (assq name substitution))
                 (let ([e (assq name context)]) (and e (vau-info? (cdr e))))))
     (let* ([specialized-arguments
              (map (lambda (a)
                     (specialize-expression a substitution environment-parameter
                                            context lambda-environment inline-fuel))
                   arguments)]
            [info (cdr (assq name context))]
            [vau-parameters (cadr info)]
            [vau-ep (caddr info)]
            [vau-body (cadddr info)])
       (specialize vau-body vau-parameters specialized-arguments vau-ep context))]

    ;; Call to local — specialize arguments + inline from lambda-environment
    [(call (var ,name local) ,arguments)
     (let ([specialized-arguments
             (map (lambda (a)
                    (specialize-expression a substitution environment-parameter
                                           context lambda-environment inline-fuel))
                  arguments)])
       (cond
         [(assq name substitution)
          => (lambda (entry)
               (let ([value (cdr entry)])
                 `(call ,(if (and (pair? value) (eq? (car value) 'alias))
                             (cadr value) value)
                         ,specialized-arguments)))]
         ;; Inline known lambda when some args are static (enables make-let fusion)
         [(and (> inline-fuel 0)
               (assq name lambda-environment)
               (exists (lambda (a)
                         (and (static-value? a)
                              ;; Exclude (quot ()) to prevent inlining explosion
                              ;; with accumulator patterns (pmatch/pmatch-elts)
                              (not (equal? a '(quot ())))))
                       specialized-arguments))
          (let* ([lam-ast (cdr (assq name lambda-environment))]
                 [result (inline-lambda lam-ast specialized-arguments
                           substitution environment-parameter context
                           lambda-environment (- inline-fuel 1))])
            (if (and result
                     (not (match lam-ast
                            [(lam ,parameters ,_)
                             (let ([free-in-result
                                     (ast-collect-free-variables result)])
                               (exists (lambda (p) (memq p free-in-result))
                                       parameters))]
                            [,_ #f])))
                result
                `(call (var ,name local) ,specialized-arguments)))]
         [else `(call (var ,name local) ,specialized-arguments)]))]

    ;; General call fallback
    [(call ,operator ,arguments)
     `(call ,(specialize-expression operator substitution environment-parameter
                                     context lambda-environment inline-fuel)
            ,(map (lambda (a)
                    (specialize-expression a substitution environment-parameter
                                           context lambda-environment inline-fuel))
                  arguments))]

    ;; Letrec — specialize bindings and body (two-pass for cross-inlining)
    [(letrec ((,names ,values) ...) ,body)
     (let* ([first-pass-values
              (map (lambda (v)
                     (specialize-expression v substitution environment-parameter
                                            context lambda-environment inline-fuel))
                   values)]
            [inner-lambda-environment
              (append
                (filter-map
                  (lambda (name-value)
                    (let ([n (car name-value)] [v (cdr name-value)])
                      (match v
                        [(lam ,p ,b) (cons n v)]
                        [(wrap (vau ,p #f ,b)) (cons n `(lam ,p ,b))]
                        [,_ #f])))
                  (map cons names first-pass-values))
                lambda-environment)]
            ;; Second pass: re-specialize values with inner-lambda-environment
            ;; so letrec bindings can inline calls to each other
            [final-values
              (if (null? inner-lambda-environment)
                  first-pass-values
                  (map (lambda (v)
                         (specialize-expression v '() #f context
                                                inner-lambda-environment inline-fuel))
                       first-pass-values))]
            ;; Rebuild lambda-environment from final values
            [final-lambda-environment
              (if (equal? final-values first-pass-values)
                  inner-lambda-environment
                  (append
                    (filter-map
                      (lambda (name-value)
                        (let ([n (car name-value)] [v (cdr name-value)])
                          (match v
                            [(lam ,p ,b) (cons n v)]
                            [(wrap (vau ,p #f ,b)) (cons n `(lam ,p ,b))]
                            [,_ #f])))
                      (map cons names final-values))
                    lambda-environment))])
       `(letrec ,(map list names final-values)
          ,(specialize-expression body substitution environment-parameter
                                  context final-lambda-environment inline-fuel)))]

    ;; Pure lambda (lam)
    [(lam ,parameters ,body)
     `(lam ,parameters
           ,(specialize-expression body substitution environment-parameter
                                    context lambda-environment inline-fuel))]

    ;; wrap(vau with #f ep)
    [(wrap (vau ,parameters #f ,body))
     (let* ([all-parameters (extract-parameter-names parameters)]
            [new-context (append
                           (map (lambda (n) (cons n 'scheme-variable)) all-parameters)
                           context)]
            [specialized-body
              (specialize-expression body substitution environment-parameter
                                     new-context lambda-environment inline-fuel)])
       `(wrap (vau ,parameters #f ,specialized-body)))]

    ;; wrap(vau with #f ep, BTA)
    [(wrap (vau ,parameters #f ,body ,binding-times))
     (let* ([all-parameters (extract-parameter-names parameters)]
            [new-context (append
                           (map (lambda (n) (cons n 'scheme-variable)) all-parameters)
                           context)]
            [specialized-body
              (specialize-expression body substitution environment-parameter
                                     new-context lambda-environment inline-fuel)])
       `(wrap (vau ,parameters #f ,specialized-body ,binding-times)))]

    ;; wrap(vau with live ep)
    [(wrap (vau ,parameters ,wrapped-ep ,body))
     (guard wrapped-ep)
     (let* ([all-parameters (extract-parameter-names parameters)]
            [new-context (append
                           (map (lambda (n) (cons n 'scheme-variable)) all-parameters)
                           context)]
            [specialized-body
              (specialize-expression body substitution environment-parameter
                                     new-context lambda-environment inline-fuel)])
       `(wrap (vau ,parameters ,wrapped-ep ,specialized-body)))]

    ;; wrap(vau with live ep, BTA)
    [(wrap (vau ,parameters ,wrapped-ep ,body ,binding-times))
     (guard wrapped-ep)
     (let* ([all-parameters (extract-parameter-names parameters)]
            [new-context (append
                           (map (lambda (n) (cons n 'scheme-variable)) all-parameters)
                           context)]
            [specialized-body
              (specialize-expression body substitution environment-parameter
                                     new-context lambda-environment inline-fuel)])
       `(wrap (vau ,parameters ,wrapped-ep ,specialized-body ,binding-times)))]

    ;; define — specialize all three sub-expressions
    [(define ,environment-expression ,name-expression ,value-expression)
     `(define ,(specialize-expression environment-expression substitution
                 environment-parameter context lambda-environment inline-fuel)
              ,(specialize-expression name-expression substitution
                 environment-parameter context lambda-environment inline-fuel)
              ,(specialize-expression value-expression substitution
                 environment-parameter context lambda-environment inline-fuel))]

    ;; Time
    [(time ,expression)
     `(time ,(specialize-expression expression substitution
               environment-parameter context lambda-environment inline-fuel))]

    ;; Anything else — pass through
    [,_ ast]))

;; =========================================================================
;; Alist Fusion: eliminate build+destructure in compiled match
;; =========================================================================
;;
;; After specialization, match vau bodies produce code that builds alists
;; via (cons (cons 'sym val) prev) then tests with (if binds ...) and
;; accesses with (cdr (assq 'sym binds)). Alist fusion rewrites these
;; patterns into direct variable bindings, eliminating the alist overhead.

;; Check if a match expression can be fully handled by thread-body.
;; Returns #t only if all leaf positions are (var _ local), (quot _), or (const #f).
(define (fusible-match? expression)
  (match expression
    ;; Rule 1: cons-bind + truthy-test
    [(let ((,x (call (var cons free)
                 ((call (var cons free) ((quot ,_) ,_val)) ,_prev))))
       (if (var ,x2 local) ,continuation (const #f)))
     (guard (eq? x x2))
     (fusible-match? continuation)]
    ;; Rule 1b: let-wrapped cons-bind + truthy-test
    [(let ((,x (let ((,_v ,_e))
                 (call (var cons free)
                   ((call (var cons free) ((quot ,_) ,_body)) ,_prev)))))
       (if (var ,x2 local) ,continuation (const #f)))
     (guard (eq? x x2))
     (fusible-match? continuation)]
    ;; Rule 2: non-cons bind + truthy-test
    [(let ((,x ,_expr)) (if (var ,x2 local) ,continuation (const #f)))
     (guard (eq? x x2))
     (fusible-match? continuation)]
    ;; Rule 3: bare cons pair
    [(call (var cons free)
       ((call (var cons free) ((quot ,_) ,_val)) ,prev))
     (fusible-match? prev)]
    ;; Rule 4: structural if
    [(if ,_test ,consequent ,alternative)
     (and (fusible-match? consequent) (fusible-match? alternative))]
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
(define (ast-has-assq-references? ast binds-name)
  (match ast
    [(call (var assq free) ((quot ,_) (var ,name local)))
     (eq? name binds-name)]
    [(let ((,_ ,values) ...) ,body)
     (or (exists (lambda (v) (ast-has-assq-references? v binds-name)) values)
         (ast-has-assq-references? body binds-name))]
    [(if ,test ,consequent ,alternative)
     (or (ast-has-assq-references? test binds-name)
         (ast-has-assq-references? consequent binds-name)
         (ast-has-assq-references? alternative binds-name))]
    [(call ,function ,arguments)
     (or (ast-has-assq-references? function binds-name)
         (exists (lambda (a) (ast-has-assq-references? a binds-name)) arguments))]
    [(letrec ((,_ ,values) ...) ,body)
     (or (exists (lambda (v) (ast-has-assq-references? v binds-name)) values)
         (ast-has-assq-references? body binds-name))]
    [,_ #f]))

;; Collect all symbol names referenced via (cdr (assq 'SYM binds))
(define (collect-assq-symbols ast binds-name)
  (match ast
    [(call (var cdr free) ((call (var assq free) ((quot ,symbol) (var ,bound-name local)))))
     (guard (eq? bound-name binds-name))
     (list symbol)]
    ;; Safe-lookup shape from compile-eval-body:
    ;;   (let ((%b (assq 'SYM binds))) (if %b (cdr %b) FALLBACK))
    ;; When fusion fires, SYM is a guaranteed pattern binding (same as above).
    [(let ((,_b (call (var assq free) ((quot ,symbol) (var ,bound-name local)))))
       (if (var ,_b2 local) (call (var cdr free) ((var ,_b3 local))) ,_fallback))
     (guard (eq? bound-name binds-name))
     (list symbol)]
    [(let ((,_ ,values) ...) ,body)
     (append (apply append (map (lambda (v) (collect-assq-symbols v binds-name)) values))
             (collect-assq-symbols body binds-name))]
    [(if ,test ,consequent ,alternative)
     (append (collect-assq-symbols test binds-name)
             (collect-assq-symbols consequent binds-name)
             (collect-assq-symbols alternative binds-name))]
    [(call ,function ,arguments)
     (append (collect-assq-symbols function binds-name)
             (apply append (map (lambda (a) (collect-assq-symbols a binds-name)) arguments)))]
    [(letrec ((,_ ,values) ...) ,body)
     (append (apply append (map (lambda (v) (collect-assq-symbols v binds-name)) values))
             (collect-assq-symbols body binds-name))]
    [,_ '()]))

;; Replace (cdr (assq 'SYM binds)) with (var SYM local) throughout AST
(define (replace-assq-references ast binds-name)
  (match ast
    [(call (var cdr free) ((call (var assq free) ((quot ,symbol) (var ,bound-name local)))))
     (guard (eq? bound-name binds-name))
     `(var ,symbol local)]
    ;; Safe-lookup shape from compile-eval-body:
    ;;   (let ((%b (assq 'SYM binds))) (if %b (cdr %b) FALLBACK))
    ;; When fusion fires SYM is guaranteed present, so the env fallback is
    ;; dead — collapse to (var SYM local) just like the plain shape.
    [(let ((,_b (call (var assq free) ((quot ,symbol) (var ,bound-name local)))))
       (if (var ,_b2 local) (call (var cdr free) ((var ,_b3 local))) ,_fallback))
     (guard (eq? bound-name binds-name))
     `(var ,symbol local)]
    [(let ((,names ,values) ...) ,body)
     `(let ,(map list names (map (lambda (v) (replace-assq-references v binds-name)) values))
        ,(replace-assq-references body binds-name))]
    [(if ,test ,consequent ,alternative)
     `(if ,(replace-assq-references test binds-name)
          ,(replace-assq-references consequent binds-name)
          ,(replace-assq-references alternative binds-name))]
    [(call ,function ,arguments)
     `(call ,(replace-assq-references function binds-name)
            ,(map (lambda (a) (replace-assq-references a binds-name)) arguments))]
    [(letrec ((,names ,values) ...) ,body)
     `(letrec ,(map list names (map (lambda (v) (replace-assq-references v binds-name)) values))
        ,(replace-assq-references body binds-name))]
    [,_ ast]))

;; Convert (var SYM free) to (var SYM local) for symbols in the given set.
;; After fusion, variables that were free (from compile-eval-body let) become
;; local once thread-body binds them directly.
(define (fix-free-to-local ast symbols)
  (match ast
    [(var ,name free) (if (memq name symbols) `(var ,name local) ast)]
    [(var ,_ ,_) ast]
    [(const ,_) ast]
    [(quot ,_) ast]
    [(dyn-env) ast]
    [(if ,test ,consequent ,alternative)
     `(if ,(fix-free-to-local test symbols)
          ,(fix-free-to-local consequent symbols)
          ,(fix-free-to-local alternative symbols))]
    [(let ((,names ,values) ...) ,body)
     `(let ,(map list names (map (lambda (v) (fix-free-to-local v symbols)) values))
        ,(fix-free-to-local body symbols))]
    [(call ,function ,arguments)
     `(call ,(fix-free-to-local function symbols)
            ,(map (lambda (a) (fix-free-to-local a symbols)) arguments))]
    [(letrec ((,names ,values) ...) ,body)
     `(letrec ,(map list names (map (lambda (v) (fix-free-to-local v symbols)) values))
        ,(fix-free-to-local body symbols))]
    [(lam ,parameters ,body)
     `(lam ,parameters ,(fix-free-to-local body symbols))]
    [(wrap (vau ,p ,e ,b))
     `(wrap (vau ,p ,e ,(fix-free-to-local b symbols)))]
    [(wrap (vau ,p ,e ,b ,bta))
     `(wrap (vau ,p ,e ,(fix-free-to-local b symbols) ,bta))]
    [,_ ast]))

;; Substitute all occurrences of (var NAME local) with REPLACEMENT in AST.
;; Stops at binding forms that shadow NAME.
(define (substitute-variable-in-ast ast name replacement)
  (match ast
    [(var ,n local) (if (eq? n name) replacement ast)]
    [(var ,_ free) ast]
    [(const ,_) ast]
    [(quot ,_) ast]
    [(dyn-env) ast]
    [(if ,test ,consequent ,alternative)
     `(if ,(substitute-variable-in-ast test name replacement)
          ,(substitute-variable-in-ast consequent name replacement)
          ,(substitute-variable-in-ast alternative name replacement))]
    [(let ((,names ,values) ...) ,body)
     (let ([new-values (map (lambda (v) (substitute-variable-in-ast v name replacement)) values)])
       (if (memq name names)
           `(let ,(map list names new-values) ,body)
           `(let ,(map list names new-values)
              ,(substitute-variable-in-ast body name replacement))))]
    [(call ,function ,arguments)
     `(call ,(substitute-variable-in-ast function name replacement)
            ,(map (lambda (a) (substitute-variable-in-ast a name replacement)) arguments))]
    [(letrec ((,names ,values) ...) ,body)
     (if (memq name names)
         ast
         `(letrec ,(map list names
                     (map (lambda (v) (substitute-variable-in-ast v name replacement)) values))
            ,(substitute-variable-in-ast body name replacement)))]
    [(lam ,parameters ,body)
     (if (memq name parameters)
         ast
         `(lam ,parameters ,(substitute-variable-in-ast body name replacement)))]
    [(define ,environment-expression ,name-expression ,value-expression)
     `(define ,(substitute-variable-in-ast environment-expression name replacement)
              ,(substitute-variable-in-ast name-expression name replacement)
              ,(substitute-variable-in-ast value-expression name replacement))]
    [,_ ast]))

;; Thread success body into match success leaves, fail into failure leaves.
;; Eliminates cons pair construction and cons-truthy tests.
(define (thread-body expression success fail)
  (match expression
    ;; Rule 1: cons-bind + truthy-test -> direct variable binding
    [(let ((,x (call (var cons free)
                 ((call (var cons free) ((quot ,symbol) ,value)) ,_prev))))
       (if (var ,x2 local) ,continuation (const #f)))
     (guard (eq? x x2))
     `(let ((,symbol ,value)) ,(thread-body continuation success fail))]

    ;; Rule 1b: let-wrapped cons-bind + truthy-test
    [(let ((,x (let ((,v ,e))
                 (call (var cons free)
                   ((call (var cons free) ((quot ,symbol) ,body)) ,_prev)))))
       (if (var ,x2 local) ,continuation (const #f)))
     (guard (eq? x x2))
     (let ([inlined-body (substitute-variable-in-ast body v e)])
       `(let ((,symbol ,inlined-body)) ,(thread-body continuation success fail)))]

    ;; Rule 2: non-cons bind + truthy-test -> convert to if
    [(let ((,x ,test-expression)) (if (var ,x2 local) ,continuation (const #f)))
     (guard (eq? x x2))
     `(if ,test-expression ,(thread-body continuation success fail) ,fail)]

    ;; Rule 3: bare cons pair
    [(call (var cons free)
       ((call (var cons free) ((quot ,symbol) ,value)) ,prev))
     `(let ((,symbol ,value)) ,(thread-body prev success fail))]

    ;; Rule 4: structural if
    [(if ,test ,consequent ,alternative)
     `(if ,test ,(thread-body consequent success fail)
                ,(thread-body alternative success fail))]

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
    [,_ expression]))

;; Walk full AST. When we find (let ([binds MATCH]) (if binds SUCCESS FAIL))
;; where SUCCESS contains assq refs to binds, fuse them.
(define (fuse-alist-lets ast)
  (match ast
    ;; Detect: (let ([binds MATCH]) (if binds SUCCESS FAIL))
    [(let ((,binds ,match-expression))
       (if (var ,binds2 local) ,success ,fail-expression))
     (guard (eq? binds binds2)
            (ast-has-assq-references? success binds)
            (fusible-match? match-expression))
     (let* ([bound-symbols (collect-assq-symbols success binds)]
            [success-clean (fix-free-to-local
                             (replace-assq-references success binds)
                             bound-symbols)]
            [match-fused (fuse-alist-lets match-expression)]
            [fail-fused (fuse-alist-lets fail-expression)])
       (thread-body match-fused success-clean fail-fused))]

    ;; Recurse into compound forms
    [(let ((,names ,values) ...) ,body)
     `(let ,(map list names (map fuse-alist-lets values))
        ,(fuse-alist-lets body))]
    [(if ,test ,consequent ,alternative)
     `(if ,(fuse-alist-lets test)
          ,(fuse-alist-lets consequent)
          ,(fuse-alist-lets alternative))]
    [(letrec ((,names ,values) ...) ,body)
     `(letrec ,(map list names (map fuse-alist-lets values))
        ,(fuse-alist-lets body))]
    [(call ,function ,arguments)
     `(call ,(fuse-alist-lets function) ,(map fuse-alist-lets arguments))]
    [(lam ,parameters ,body) `(lam ,parameters ,(fuse-alist-lets body))]
    [(wrap (vau ,p ,e ,b)) `(wrap (vau ,p ,e ,(fuse-alist-lets b)))]
    [(wrap (vau ,p ,e ,b ,bta)) `(wrap (vau ,p ,e ,(fuse-alist-lets b) ,bta))]
    [(define ,environment-expression ,name-expression ,value-expression)
     `(define ,(fuse-alist-lets environment-expression)
              ,(fuse-alist-lets name-expression)
              ,(fuse-alist-lets value-expression))]
    [,_ ast]))

;; -------------------------------------------------------------------------
;; Define helpers for codegen
;; -------------------------------------------------------------------------

;; Extract the symbol name from a define name expression.
(define (extract-define-name-symbol name-ast)
  (match name-ast
    [(quot ,name) (and (symbol? name) name)]
    [(var ,name free) name]
    [,_ #f]))

;; Extract top-level define nodes from a specialized AST.
;; Returns (list names values stripped-body).
(define (collect-define-nodes ast)
  (define (flatten-begins expressions)
    (cond
      [(null? expressions) '()]
      [(match (car expressions) [(begin ,inner ...) inner] [,_ #f])
       => (lambda (inner) (flatten-begins (append inner (cdr expressions))))]
      [else (cons (car expressions) (flatten-begins (cdr expressions)))]))
  (match ast
    [(begin ,expressions ...)
     (let loop ([es (flatten-begins expressions)]
                [names '()] [values '()] [other '()])
       (if (null? es)
           (list (reverse names) (reverse values)
                 (cond [(null? other) '(const #f)]
                       [(= (length other) 1) (car other)]
                       [else `(begin ,@(reverse other))]))
           (match (car es)
             [(define (dyn-env) ,name-expression ,value-expression)
              (let ([symbol (extract-define-name-symbol name-expression)])
                (if symbol
                    (loop (cdr es) (cons symbol names)
                          (cons value-expression values) other)
                    (loop (cdr es) names values (cons (car es) other))))]
             ;; Recurse into letrec bodies to find defines from unrolled loops
             [(letrec ,bindings ,body)
              (let* ([inner (collect-define-nodes body)]
                     [inner-names (car inner)]
                     [inner-values (cadr inner)]
                     [inner-rest (caddr inner)])
                (if (null? inner-names)
                    (loop (cdr es) names values (cons (car es) other))
                    (let ([rest (if (equal? inner-rest '(const #f))
                                   '()
                                   (list `(letrec ,bindings ,inner-rest)))])
                      (loop (cdr es)
                            (append (reverse inner-names) names)
                            (append (reverse inner-values) values)
                            (append (reverse rest) other)))))]
             [,_ (loop (cdr es) names values (cons (car es) other))])))]
    [(define (dyn-env) ,name-expression ,value-expression)
     (let ([symbol (extract-define-name-symbol name-expression)])
       (if symbol
           (list (list symbol) (list value-expression) '(const #f))
           (list '() '() ast)))]
    [,_ (list '() '() ast)]))

;; Unwrap let/letrec layers from an AST to expose the core expression.
(define (unwrap-structural-bindings ast)
  (match ast
    [(let ,bindings ,body)
     (let ([result (unwrap-structural-bindings body)])
       (list (cons `(let ,bindings) (car result)) (cadr result)))]
    [(letrec ,bindings ,body)
     (let ([result (unwrap-structural-bindings body)])
       (list (cons `(letrec ,bindings) (car result)) (cadr result)))]
    [,_ (list '() ast)]))

;; Re-wrap compiled code with let/letrec layers.
(define (rewrap-with-compiled-bindings wrappers code context)
  (fold-right
    (lambda (wrapper code)
      (match wrapper
        [(let ,bindings)
         `(let ,(map (lambda (b) (list (car b) (generate-code-in-context (cadr b) context)))
                     bindings)
            ,code)]
        [(letrec ,bindings)
         `(letrec ,(map (lambda (b) (list (car b) (generate-code-in-context (cadr b) context)))
                        bindings)
            ,code)]))
    code
    wrappers))

;; Find a sub-expression vau call with defines inside an AST.
;; Returns #f or (list placeholder-sym vau-name vau-arguments ast-with-placeholder).
;; Only looks one level deep into call arguments.
(define (find-sub-expression-vau-call ast context)
  (match ast
    [(call ,operator ,arguments)
     (let scan ([remaining arguments] [index 0] [before '()])
       (if (null? remaining) #f
           (match (car remaining)
             [(call (var ,name local) ,vau-arguments)
              (guard (let ([entry (assq name context)])
                       (and entry (vau-info? (cdr entry))
                            (ast-has-define? (cadddr (cdr entry))))))
              (let ([placeholder (gensym "vau-result")])
                (list placeholder name vau-arguments
                      `(call ,operator ,(append (reverse before)
                                                (cons `(var ,placeholder local)
                                                      (cdr remaining))))))]
             [,_ (scan (cdr remaining) (+ index 1) (cons (car remaining) before))])))]
    [,_ #f]))

;; -------------------------------------------------------------------------
;; Context-aware code generation
;; -------------------------------------------------------------------------

(define (generate-code ast)
  (generate-code-in-context ast '()))

;; Process a begin's expression list, restructuring vau calls with define
;; into call-with-values chains.
(define (generate-code-for-begin expressions context)
  (let loop ([es expressions] [done '()])
    (cond
      [(null? es)
       (let ([compiled (reverse done)])
         (cond [(null? compiled) '(void)]
               [(= (length compiled) 1) (car compiled)]
               [else `(begin ,@compiled)]))]
      [else
       (let ([expression (car es)])
         (match expression
           ;; Known vau call whose body has define — (values news out) convention
           [(call (var ,name local) ,arguments)
            (guard (and (not (null? (cdr es)))
                        (let ([entry (assq name context)])
                          (and entry (vau-info? (cdr entry))
                               (ast-has-define? (cadddr (cdr entry)))))))
            (let* ([info (cdr (assq name context))]
                   [vau-parameters (cadr info)]
                   [vau-ep (caddr info)]
                   [vau-body (cadddr info)]
                   [specialized (specialize vau-body vau-parameters arguments
                                            vau-ep context)]
                   [unwrapped (unwrap-structural-bindings specialized)]
                   [wrappers (car unwrapped)]
                   [core (cadr unwrapped)]
                   [defines (collect-define-nodes core)]
                   [define-names (car defines)]
                   [define-values (cadr defines)]
                   [stripped-body (caddr defines)])
              (if (null? define-names)
                  ;; No defines found after specialization — compile normally
                  (loop (cdr es) (cons (generate-code-in-context specialized context) done))
                  (if (ast-has-define? stripped-body)
                      ;; Some defines couldn't be extracted (dynamic names).
                      ;; Fall back to runtime operative call — the operative returns
                      ;; (values news result) and we merge news into env dynamically.
                      (let* ([syntax-arguments
                               (map (lambda (a) `',(ast-to-source-form a)) arguments)]
                             [runtime-call
                               `(call-with-values
                                  (lambda () ((cdr ,name) env ,@syntax-arguments))
                                  (lambda (%news %result)
                                    (for-each (lambda (pair)
                                                (set-cdr! env (cons (car env) (cdr env)))
                                                (set-car! env pair))
                                              %news)
                                    ,(generate-code-for-begin (cdr es) context)))])
                        (if (null? done)
                            runtime-call
                            `(begin ,@(reverse done) ,runtime-call)))
                  (let* ([body-free (ast-collect-free-variables stripped-body)]
                         [body-references-defines
                           (or (exists (lambda (n) (memq n body-free)) define-names)
                               (ast-references-environment? stripped-body))]
                         [value-codes (map (lambda (v) (generate-code-in-context v context))
                                          define-values)]
                         [new-context (append
                                        (map (lambda (n) (cons n 'scheme-variable))
                                             define-names)
                                        context)]
                         [body-code (if body-references-defines
                                        (generate-code-in-context stripped-body new-context)
                                        (generate-code-in-context stripped-body context))]
                         [inner-values (if body-references-defines
                                           `(values (list ,@value-codes) (list (void)))
                                           `(values (list ,@value-codes) (list ,body-code)))]
                         [producer `(lambda ()
                                      ,(rewrap-with-compiled-bindings
                                         wrappers inner-values context))]
                         [continuation-body
                           (if body-references-defines
                               `(begin ,body-code
                                       ,(generate-code-for-begin (cdr es) new-context))
                               (generate-code-for-begin (cdr es) new-context))]
                         [call-with-values-form
                           `(call-with-values ,producer
                              (lambda (news out)
                                (call-with-values (lambda () (apply values news))
                                  (lambda ,define-names
                                    ,continuation-body))))])
                    (if (null? done)
                        call-with-values-form
                        `(begin ,@(reverse done) ,call-with-values-form))))))]

           ;; Raw define with static name — compile mutation AND add let binding
           [(define ,environment-expression (quot ,define-name) ,value-expression)
            (guard (and (symbol? define-name)
                        (not (null? (cdr es)))))
            (let* ([define-code (generate-code-in-context expression context)]
                   [value-code (generate-code-in-context value-expression context)]
                   [new-context (cons (cons define-name 'scheme-variable) context)]
                   [continuation (generate-code-for-begin (cdr es) new-context)])
              (if (null? done)
                  `(begin ,define-code
                          (let ([,define-name ,value-code]) ,continuation))
                  `(begin ,@(reverse done) ,define-code
                          (let ([,define-name ,value-code]) ,continuation))))]

           ;; Default — check for sub-expression vau call that needs hoisting
           [,_
            (let ([hoisted (and (not (null? (cdr es)))
                                (find-sub-expression-vau-call expression context))])
              (if hoisted
                  ;; Hoist: specialize the vau call, collect defines,
                  ;; wrap with call-with-values, compile remainder with new context
                  (let* ([placeholder (car hoisted)]
                         [vau-name (cadr hoisted)]
                         [vau-arguments (caddr hoisted)]
                         [modified-expression (cadddr hoisted)]
                         [info (cdr (assq vau-name context))]
                         [vau-parameters (cadr info)]
                         [vau-ep (caddr info)]
                         [vau-body (cadddr info)]
                         [specialized (specialize vau-body vau-parameters
                                                  vau-arguments vau-ep context)]
                         [unwrapped (unwrap-structural-bindings specialized)]
                         [wrappers (car unwrapped)]
                         [core (cadr unwrapped)]
                         [defines (collect-define-nodes core)]
                         [define-names (car defines)]
                         [define-values (cadr defines)]
                         [stripped-body (caddr defines)])
                    (if (null? define-names)
                        (loop (cdr es)
                              (cons (generate-code-in-context expression context) done))
                        (let* ([value-codes (map (lambda (v) (generate-code-in-context v context))
                                                 define-values)]
                               [body-code (generate-code-in-context stripped-body context)]
                               [inner-values `(values (list ,@value-codes) (list ,body-code))]
                               [producer `(lambda ()
                                            ,(rewrap-with-compiled-bindings
                                               wrappers inner-values context))]
                               [new-context
                                 (append (cons (cons placeholder 'scheme-variable)
                                               (map (lambda (n) (cons n 'scheme-variable))
                                                    define-names))
                                         context)]
                               [continuation
                                 (generate-code-for-begin
                                   (cons modified-expression (cdr es)) new-context)]
                               [call-with-values-form
                                 `(call-with-values ,producer
                                    (lambda (news out)
                                      (call-with-values (lambda () (apply values news))
                                        (lambda ,define-names
                                          (call-with-values (lambda () (apply values out))
                                            (lambda (,placeholder)
                                              ,continuation))))))])
                          (if (null? done)
                              call-with-values-form
                              `(begin ,@(reverse done) ,call-with-values-form)))))
                  ;; No sub-expression vau call — compile normally
                  (loop (cdr es)
                        (cons (generate-code-in-context expression context) done))))]))])))

;; The main code generation function, threading context through.
(define (generate-code-in-context ast context)
  (match ast
    [(const ,value)
     (if (or (null? value) (string? value)) `',value value)]

    [(var ,name local) name]

    [(var ,name free)
     (cond
       ;; Known in context (bound by call-with-values from define) -> bare variable
       [(assq name context) name]
       ;; In vau bodies with live ep, free variables are looked up
       ;; from the runtime environment alist.
       [(assq '%has-environment context)
        `(environment-lookup ',name env)]
       [else name])]

    [(quot ,datum) `',datum]

    [(if ,test ,consequent ,alternative)
     `(if ,(generate-code-in-context test context)
          ,(generate-code-in-context consequent context)
          ,(generate-code-in-context alternative context))]

    [(begin ,expressions ...)
     (generate-code-for-begin expressions context)]

    [(lam ,parameters ,body)
     `(lambda ,parameters ,(generate-code-in-context body context))]

    [(let ((,names ,values) ...) ,body)
     ;; Classify bindings the same way as letrec: detect lam/vau for context.
     (let* ([binding-info
              (map (lambda (name value)
                     (match value
                       [(lam ,p ,body) (list name 'direct value)]
                       [(wrap (vau ,p ,ep ,body ,bta))
                        (list name 'direct value)]
                       [(wrap (vau ,p ,ep ,body))
                        (list name 'direct value)]
                       [(vau ,p ,ep ,body ,bta)
                        (guard ep)
                        (list name 'vau value)]
                       [(vau ,p #f ,body)
                        (list name 'vau value)]
                       [,_ (list name 'other value)]))
                   names values)]
            [new-context
              (append
                (map
                  (lambda (info)
                    (let ([name (car info)]
                          [kind (cadr info)]
                          [value (caddr info)])
                      (cond
                        [(eq? kind 'direct) (cons name (list 'direct value))]
                        [(eq? kind 'vau)
                         (match value
                           [(vau ,p ,ep ,body ,bta)
                            (cons name `(vau-info ,p ,ep ,body))]
                           [(vau ,p ,ep ,body)
                            (cons name `(vau-info ,p ,ep ,body))])]
                        [else (cons name 'scheme-variable)])))
                  binding-info)
                context)]
            [has-vau (exists (lambda (info) (eq? (cadr info) 'vau)) binding-info)]
            [body-context (if has-vau
                              (cons '(%has-environment . #t) new-context)
                              new-context)]
            [compiled-bindings
              (map (lambda (info)
                     (list (car info) (generate-code-in-context (caddr info) new-context)))
                   binding-info)]
            [body-code (generate-code-in-context body body-context)])
       (if has-vau
           `(let ,compiled-bindings
              (let ([env (list* ,@(map (lambda (n) `(cons ',n ,n)) names) env)])
                ,body-code))
           `(let ,compiled-bindings ,body-code)))]

    ;; Named-let optimization: single-binding letrec with immediate call
    [(letrec ((,names ,values) ...) (call (var ,call-name local) ,call-arguments))
     (guard (and (= (length names) 1)
                 (eq? (car names) call-name)
                 (= (length call-arguments)
                    (length (match (car values) [(lam ,p ,_) p] [,_ '()])))
                 (match (car values) [(lam ,p ,_) (list? p)] [,_ #f])))
     (let ([name (car names)]
           [value (car values)])
       (match value
         [(lam ,parameters ,lambda-body)
          (let* ([new-context (cons (cons name (list 'direct value)) context)]
                 [compiled-arguments
                   (map (lambda (a) (generate-code-in-context a context))
                        call-arguments)]
                 [compiled-body
                   (generate-code-in-context lambda-body new-context)])
            `(let ,name ,(map list parameters compiled-arguments)
               ,compiled-body))]))]

    ;; Letrec — classify each binding and build context
    [(letrec ((,names ,values) ...) ,body)
     (let* ([binding-info
              (map (lambda (name value)
                     (match value
                       [(lam ,p ,body) (list name 'direct value)]
                       [(wrap (vau ,p ,ep ,body ,bta))
                        (list name 'direct value)]
                       [(wrap (vau ,p ,ep ,body))
                        (list name 'direct value)]
                       [(vau ,p ,ep ,body ,bta)
                        (guard ep)
                        (list name 'vau value)]
                       [(vau ,p #f ,body)
                        (list name 'vau value)]
                       [,_ (list name 'other value)]))
                   names values)]
            [new-context
              (append
                (filter-map
                  (lambda (info)
                    (let ([name (car info)]
                          [kind (cadr info)]
                          [value (caddr info)])
                      (cond
                        [(eq? kind 'direct) (cons name (list 'direct value))]
                        [(eq? kind 'vau)
                         (match value
                           [(vau ,p ,ep ,body ,bta)
                            (cons name `(vau-info ,p ,ep ,body))]
                           [(vau ,p ,ep ,body)
                            (cons name `(vau-info ,p ,ep ,body))])]
                        [else #f])))
                  binding-info)
                context)]
            [compiled-bindings
              (map (lambda (info)
                     (list (car info) (generate-code-in-context (caddr info) new-context)))
                   binding-info)])
       ;; Extend dynamic environment with letrec bindings so that
       ;; eval'd code (via seed-evaluate) can reference user-defined functions.
       (let* ([has-vau (exists (lambda (info) (eq? (cadr info) 'vau)) binding-info)]
              [body-context (if has-vau
                                (cons '(%has-environment . #t) new-context)
                                new-context)]
              [body-code (generate-code-in-context body body-context)])
         (if has-vau
             `(letrec ,compiled-bindings
                (let ([env (list* ,@(map (lambda (n) `(cons ',n ,n)) names) env)])
                  ,body-code))
             `(letrec ,compiled-bindings ,body-code))))]

    ;; --- Call-site dispatch ---

    ;; Call to known direct lam -> (name arguments...)
    [(call (var ,name local) ,arguments)
     (guard (let ([e (assq name context)])
              (and e (pair? (cdr e)) (eq? (cadr e) 'direct))))
     `(,name ,@(map (lambda (a) (generate-code-in-context a context)) arguments))]

    ;; Call to known vau -> SPECIALIZE at compile time
    [(call (var ,name local) ,arguments)
     (guard (let ([e (assq name context)])
              (and e (vau-info? (cdr e)))))
     (let* ([info (cdr (assq name context))]
            [vau-parameters (cadr info)]
            [vau-ep (caddr info)]
            [vau-body (cadddr info)])
       (generate-code-in-context
         (specialize vau-body vau-parameters arguments vau-ep context)
         context))]

    ;; Call to other local — may be operative or applicative
    [(call (var ,name local) ,arguments)
     (let ([argument-codes
             (map (lambda (a) (generate-code-in-context a context)) arguments)])
       ;; Only emit operative dispatch when env is available (inside vau body)
       (if (assq '%has-environment context)
           (let* ([syntax-arguments
                    (map (lambda (a) `',(ast-to-source-form a)) arguments)]
                  [locals (build-operative-environment-extension syntax-arguments context)])
             `(let ([proc ,name])
                (if (and (pair? proc) (eq? (car proc) 'operative))
                    ,(wrap-operative-call-with-environment
                       locals `((cdr proc) env ,@syntax-arguments))
                    (proc ,@argument-codes))))
           ;; No env in scope — still check for operative (may be passed as argument)
           (let* ([syntax-arguments
                    (map (lambda (a) `',(ast-to-source-form a)) arguments)])
             `(let ([proc ,name])
                (if (and (pair? proc) (eq? (car proc) 'operative))
                    ((cdr proc) '() ,@syntax-arguments)
                    (proc ,@argument-codes))))))]

    ;; Call to free — may be operative or applicative
    [(call (var ,name free) ,arguments)
     (let ([argument-codes
             (map (lambda (a) (generate-code-in-context a context)) arguments)])
       (if (assq '%has-environment context)
           ;; Inside vau body — dispatch with operative check
           (let* ([syntax-arguments
                    (map (lambda (a) `',(ast-to-source-form a)) arguments)]
                  [locals (build-operative-environment-extension syntax-arguments context)])
             (if (not (assq name context))
                 ;; Not in context -> look up from environment
                 `(let ([proc (environment-lookup ',name env)])
                    (if (and (pair? proc) (eq? (car proc) 'operative))
                        ,(wrap-operative-call-with-environment
                           locals `((cdr proc) env ,@syntax-arguments))
                        (proc ,@argument-codes)))
                 ;; In context -> bare name with dispatch
                 `(let ([proc ,name])
                    (if (and (pair? proc) (eq? (car proc) 'operative))
                        ,(wrap-operative-call-with-environment
                           locals `((cdr proc) env ,@syntax-arguments))
                        (proc ,@argument-codes)))))
           ;; No env in scope — direct call
           `(,name ,@argument-codes)))]

    ;; Generic call — runtime dispatch
    [(call ,operator ,arguments)
     (let* ([operator-code (generate-code-in-context operator context)]
            [argument-codes
              (map (lambda (a) (generate-code-in-context a context)) arguments)]
            [syntax-arguments
              (map (lambda (a) `',(ast-to-source-form a)) arguments)]
            [locals (build-operative-environment-extension syntax-arguments context)])
       `(let ([proc ,operator-code])
          (if (and (pair? proc) (eq? (car proc) 'operative))
              ,(wrap-operative-call-with-environment
                 locals
                 `(call-with-values
                    (lambda () ((cdr proc) env ,@syntax-arguments))
                    (lambda (%news %result) %result)))
              (proc ,@argument-codes))))]

    ;; Eval -> seed-evaluate fallback
    [(eval ,expression ,environment)
     `(seed-evaluate ,(generate-code-in-context expression context)
                     ,(generate-code-in-context environment context))]

    ;; Time
    [(time ,expression)
     `(time ,(generate-code-in-context expression context))]

    ;; BTA-annotated vau (5-field) with live environment-parameter
    [(vau ,parameters ,environment-parameter ,body ,binding-times)
     (guard environment-parameter)
     (let* ([all-parameters (extract-parameter-names parameters)]
            [has-define (ast-has-define? body)]
            [new-context
              (cons '(%has-environment . #t)
                (append (if has-define '((%has-news . #t)) '())
                        (map (lambda (n) (cons n 'scheme-variable)) all-parameters)
                        context))]
            [body-code (generate-code-in-context body new-context)])
       `(cons 'operative
              (lambda (env . ,parameters)
                (let ([,environment-parameter env]
                      ,@(if has-define '([%news '()]) '()))
                  ,(if has-define
                       `(let ([%result ,body-code])
                          (values (reverse %news) %result))
                       body-code)))))]

    ;; Vau with #f environment-parameter
    [(vau ,parameters ,ep ,body)
     (guard (not ep))
     (let* ([all-parameters (extract-parameter-names parameters)]
            [has-define (ast-has-define? body)]
            [new-context
              (append (if has-define '((%has-news . #t)) '())
                      (map (lambda (n) (cons n 'scheme-variable)) all-parameters)
                      context)]
            [body-code (generate-code-in-context body new-context)])
       `(cons 'operative
              (lambda (env . ,parameters)
                ,(if has-define
                     `(let ([%news '()])
                        (let ([%result ,body-code])
                          (values (reverse %news) %result)))
                     body-code))))]

    ;; wrap(vau with live ep, BTA) -> impure applicative
    [(wrap (vau ,parameters ,environment-parameter ,body ,binding-times))
     (guard environment-parameter)
     (let* ([all-parameters (extract-parameter-names parameters)]
            [new-context
              (cons '(%has-environment . #t)
                (append (map (lambda (n) (cons n 'scheme-variable)) all-parameters)
                        context))]
            [body-code (generate-code-in-context body new-context)])
       `(lambda ,parameters
          (let ([env (list* ,@(map (lambda (n) `(cons ',n ,n)) all-parameters) env)])
            (let ([,environment-parameter env]) ,body-code))))]

    ;; wrap(vau with live ep, no BTA)
    [(wrap (vau ,parameters ,environment-parameter ,body))
     (guard environment-parameter)
     (let* ([all-parameters (extract-parameter-names parameters)]
            [new-context
              (cons '(%has-environment . #t)
                (append (map (lambda (n) (cons n 'scheme-variable)) all-parameters)
                        context))]
            [body-code (generate-code-in-context body new-context)])
       `(lambda ,parameters
          (let ([env (list* ,@(map (lambda (n) `(cons ',n ,n)) all-parameters) env)])
            (let ([,environment-parameter env]) ,body-code))))]

    ;; wrap(vau with #f ep) that was not lowered to lam (has free variables)
    [(wrap (vau ,parameters ,ep ,body))
     (guard (not ep))
     (let* ([all-parameters (extract-parameter-names parameters)]
            [new-context
              (append (map (lambda (n) (cons n 'scheme-variable)) all-parameters)
                      context)]
            [body-code (generate-code-in-context body new-context)])
       (if (not (ast-references-environment? body))
           `(lambda ,parameters ,body-code)
           `(lambda ,parameters
              (let ([env (list* ,@(map (lambda (n) `(cons ',n ,n)) all-parameters) env)])
                ,body-code))))]

    ;; Generic wrap
    [(wrap ,inner) (generate-code-in-context inner context)]

    ;; Dynamic calling environment
    [(dyn-env) 'env]

    ;; Define — inside operative body: immutable extension + accumulate into %news
    ;;          outside (sub-expression fallback): mutate environment alist
    [(define ,environment-expression ,name-expression ,value-expression)
     (let ([environment-code (generate-code-in-context environment-expression context)]
           [name-code (generate-code-in-context name-expression context)]
           [value-code (generate-code-in-context value-expression context)])
       (if (assq '%has-news context)
           ;; Inside operative body — immutable extension + accumulate
           `(let ([v ,value-code])
              (set! env (cons (cons ,name-code v) env))
              (set! %news (cons (cons ,name-code v) %news))
              v)
           ;; Sub-expression fallback — mutate environment alist
           `(let ([target ,environment-code] [name ,name-code] [v ,value-code])
              (set-cdr! target (cons (car target) (cdr target)))
              (set-car! target (cons name v))
              v)))]

    [,x (error 'generate-code "unknown form" x)]))

;; =========================================================================
;; Runtime
;; =========================================================================

;; Simple alist lookup for runtime environment.
(define (environment-lookup name env)
  (cond [(assq name env) => cdr]
        [else (error 'environment-lookup "unbound" name)]))

;; Alist lookup with auto-unbox for letrec boxes in interpreter.
(define (environment-lookup-unbox name env)
  (cond [(assq name env) =>
         (lambda (binding)
           (let ([value (cdr binding)])
             (if (box? value) (unbox value) value)))]
        [else (error 'environment-lookup-unbox "unbound" name)]))

;; Bind parameter tree to argument list, extending environment.
(define (bind-parameters parameters arguments env)
  (cond
    [(symbol? parameters) (cons (cons parameters arguments) env)]
    [(null? parameters) env]
    [(pair? parameters)
     (bind-parameters (cdr parameters) (cdr arguments)
                      (bind-parameters (car parameters) (car arguments) env))]
    [else env]))

;; =========================================================================
;; Interpreter fallback: seed-evaluate
;; =========================================================================

;; Evaluate a statement, returning (values result new-env).
;; Used by begin/let to thread environment through sequential expressions.
(define (seed-evaluate-statement expression env)
  (define (thread-body expressions env)
    (let loop ([es expressions] [env env] [result #f])
      (if (null? es) (values result env)
          (call-with-values
            (lambda () (seed-evaluate-statement (car es) env))
            (lambda (value new-env)
              (loop (cdr es) new-env value))))))
  (match expression
    ;; Begin — thread environment through elements
    [(begin . ,expressions) (thread-body expressions env)]
    ;; Let — thread environment through bindings then body
    [(let ,bindings . ,bodies)
     (let loop ([bs bindings] [env env])
       (if (null? bs)
           (thread-body bodies env)
           (let* ([binding (car bs)]
                  [name (car binding)]
                  [value (seed-evaluate (cadr binding) env)])
             (loop (cdr bs) (cons (cons name value) env)))))]
    ;; Local define (simple) — extend environment immutably
    [(define ,name ,value)
     (guard (and (symbol? name) (not (pair? name))))
     (let ([v (seed-evaluate value env)])
       (values v (cons (cons name v) env)))]
    ;; 3-arg define — extend target environment + thread environment
    [(define ,target-env-expression ,name-expression ,value-expression)
     (guard (symbol? name-expression))
     (let ([target-env (seed-evaluate target-env-expression env)]
           [v (seed-evaluate value-expression env)])
       (set-cdr! target-env (cons (car target-env) (cdr target-env)))
       (set-car! target-env (cons name-expression v))
       (values v (cons (cons name-expression v) env)))]
    ;; Local define (destructuring)
    [(define (,names ...) ,expression)
     (let ([result-list (seed-evaluate expression env)])
       (let loop ([ns names] [index 0] [env env])
         (if (null? ns) (values (void) env)
             (loop (cdr ns) (+ index 1)
                   (cons (cons (car ns) (list-ref result-list index)) env)))))]
    ;; Application — operative calls propagate news into environment
    [(,operator . ,arguments)
     (guard (and (pair? expression)
                 (not (memq operator '(quote if eval let letrec
                                        lambda vau define)))))
     (let ([proc (seed-evaluate operator env)])
       (if (and (pair? proc) (eq? (car proc) 'operative))
           (call-with-values
             (lambda () (apply (cdr proc) env arguments))
             (lambda (news result)
               (values result (append news env))))
           (let ([evaluated-arguments
                   (map (lambda (a) (seed-evaluate a env)) arguments)])
             (values (apply proc evaluated-arguments) env))))]
    ;; Everything else — environment unchanged
    [,_ (values (seed-evaluate expression env) env)]))

;; The interpreter fallback for eval (vau programs).
(define (seed-evaluate expression env)
  (match expression
    [,s (guard (symbol? s)) (environment-lookup-unbox s env)]
    [,n (guard (null? n)) n]
    [(,head ,datum) (guard (eq? head 'quote)) datum]
    [(if ,test ,consequent ,alternative)
     (if (seed-evaluate test env)
         (seed-evaluate consequent env)
         (seed-evaluate alternative env))]
    [(eval ,expression ,environment)
     (seed-evaluate (seed-evaluate expression env) (seed-evaluate environment env))]
    [(begin . ,expressions)
     (let loop ([es expressions] [env env] [result #f])
       (if (null? es) result
           (call-with-values
             (lambda () (seed-evaluate-statement (car es) env))
             (lambda (value new-env)
               (loop (cdr es) new-env value)))))]
    ;; Named let
    [(let ,name ,bindings . ,bodies)
     (guard (symbol? name))
     (let* ([parameters (map car bindings)]
            [initial-values
              (map (lambda (b) (seed-evaluate (cadr b) env)) bindings)]
            [proc (seed-evaluate `(lambda ,parameters ,@bodies) env)]
            [env (cons (cons name proc) env)])
       (apply proc initial-values))]
    ;; Regular let
    [(let ,bindings . ,bodies)
     (let loop ([bs bindings] [env env])
       (if (null? bs)
           (let body-loop ([es bodies] [env env] [result (void)])
             (if (null? es) result
                 (call-with-values
                   (lambda () (seed-evaluate-statement (car es) env))
                   (lambda (value new-env)
                     (body-loop (cdr es) new-env value)))))
           (let* ([binding (car bs)]
                  [name (car binding)]
                  [value (seed-evaluate (cadr binding) env)])
             (loop (cdr bs) (cons (cons name value) env)))))]
    [(letrec ,bindings ,body)
     (let* ([names (map car bindings)]
            [boxes (map (lambda (_) (box #f)) bindings)]
            [env-with-boxes
              (fold-left (lambda (e name-box)
                           (cons (cons (car name-box) (cdr name-box)) e))
                         env
                         (map cons names boxes))])
       (for-each (lambda (binding bx)
                   (set-box! bx (seed-evaluate (cadr binding) env-with-boxes)))
                 bindings boxes)
       (seed-evaluate body env-with-boxes))]
    [(lambda ,parameters ,body)
     (if (symbol? parameters)
         (lambda values
           (seed-evaluate body (cons (cons parameters values) env)))
         (lambda values
           (seed-evaluate body (bind-parameters parameters values env))))]
    [(vau ,parameters ,ep ,body)
     (cons 'operative
           (if (symbol? parameters)
               (lambda (dynamic-env . syntaxes)
                 (let* ([new-env (cons (cons parameters syntaxes) env)]
                        [new-env (if (or (eq? ep '_) (eq? ep '%ignore) (not ep))
                                     new-env
                                     (cons (cons ep dynamic-env) new-env))])
                   (values '() (seed-evaluate body new-env))))
               (lambda (dynamic-env . syntaxes)
                 (let* ([new-env (bind-parameters parameters syntaxes env)]
                        [new-env (if (or (eq? ep '_) (eq? ep '%ignore) (not ep))
                                     new-env
                                     (cons (cons ep dynamic-env) new-env))])
                   (values '() (seed-evaluate body new-env))))))]
    ;; Define (destructuring, local)
    [(define (,names ...) ,expression)
     (let ([values (seed-evaluate expression env)])
       (let loop ([ns names] [index 0])
         (if (null? ns) (void)
             (begin
               (set-cdr! env (cons (car env) (cdr env)))
               (set-car! env (cons (car ns) (list-ref values index)))
               (loop (cdr ns) (+ index 1))))))]
    ;; Define (simple, local)
    [(define ,name ,value)
     (guard (symbol? name))
     (let ([v (seed-evaluate value env)])
       (set-cdr! env (cons (car env) (cdr env)))
       (set-car! env (cons name v))
       v)]
    ;; Define (3-arg, target environment)
    [(define ,target-env-expression ,name-expression ,value-expression)
     (guard (symbol? name-expression))
     (let ([target-env (seed-evaluate target-env-expression env)]
           [v (seed-evaluate value-expression env)])
       (set-cdr! target-env (cons (car target-env) (cdr target-env)))
       (set-car! target-env (cons name-expression v))
       v)]
    ;; Define (4-arg, destructuring into target environment)
    [(define ,target-env-expression (,names ...) ,expression)
     (let ([target-env (seed-evaluate target-env-expression env)]
           [values (seed-evaluate expression env)])
       (let loop ([ns names] [index 0])
         (if (null? ns) (void)
             (begin
               (set-cdr! target-env (cons (car target-env) (cdr target-env)))
               (set-car! target-env (cons (car ns) (list-ref values index)))
               (loop (cdr ns) (+ index 1))))))]
    ;; Application
    [(,operator . ,arguments)
     (let ([proc (seed-evaluate operator env)])
       (if (and (pair? proc) (eq? (car proc) 'operative))
           (call-with-values
             (lambda () (apply (cdr proc) env arguments))
             (lambda (news result) result))
           (let ([evaluated-arguments
                   (map (lambda (a) (seed-evaluate a env)) arguments)])
             (apply proc evaluated-arguments))))]
    [,n (guard (number? n)) n]
    [,b (guard (boolean? b)) b]
    [,s (guard (string? s)) s]
    [() '()]
    [,p (guard (procedure? p)) p]
    [,x (guard (eq? x (void))) x]
    [_ (error 'seed-evaluate "unknown" expression)]))

;; =========================================================================
;; Ground Environment
;; =========================================================================

(define environment-ground
  `((+ . ,+) (- . ,-) (* . ,*) (/ . ,/)
    (< . ,<) (> . ,>) (= . ,=) (>= . ,>=) (<= . ,<=)
    (cons . ,cons) (car . ,car) (cdr . ,cdr)
    (caar . ,caar) (cadr . ,cadr) (cdar . ,cdar) (cddr . ,cddr)
    (caaar . ,caaar) (caadr . ,caadr) (cadar . ,cadar) (caddr . ,caddr)
    (cdaar . ,cdaar) (cdadr . ,cdadr) (cddar . ,cddar) (cdddr . ,cdddr)
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
    (list* . ,list*)
    (for-each . ,for-each)
    (iota . ,(lambda (n)
      (let loop ([i 0] [accumulator '()])
        (if (= i n) (reverse accumulator)
            (loop (+ i 1) (cons i accumulator))))))
    ;; Disjoint encapsulation types (Kernel primitive)
    (make-encapsulation-type . ,(lambda ()
      (let ([tag (gensym "encapsulation")])
        (list
          (lambda (value) (cons tag value))
          (lambda (x) (and (pair? x) (eq? (car x) tag)))
          (lambda (x) (cdr x))))))
    ;; Symbols for constructing expressions (used by provide, define-record-type etc.)
    (define . define) (let . let) (begin . begin)
    ;; Operatives for the interpreter — all return (values '() result)
    (quote . ,(cons 'operative (lambda (env x) (values '() x))))
    (if . ,(cons 'operative
                 (lambda (env test consequent . alternative)
                   (values '()
                     (if (seed-evaluate test env)
                         (seed-evaluate consequent env)
                         (if (null? alternative)
                             (void)
                             (seed-evaluate (car alternative) env)))))))
    (begin . ,(cons 'operative
                (lambda (env . body)
                  (values '()
                    (fold-left (lambda (_ e) (seed-evaluate e env)) (void) body)))))
    (when . ,(cons 'operative
                (lambda (env test . body)
                  (if (seed-evaluate test env)
                      (let loop ([es body] [env env] [result (void)])
                        (if (null? es) (values '() result)
                            (call-with-values
                              (lambda () (seed-evaluate-statement (car es) env))
                              (lambda (value new-env)
                                (loop (cdr es) new-env value)))))
                      (values '() (void))))))
    (unless . ,(cons 'operative
                  (lambda (env test . body)
                    (if (not (seed-evaluate test env))
                        (let loop ([es body] [env env] [result (void)])
                          (if (null? es) (values '() result)
                              (call-with-values
                                (lambda () (seed-evaluate-statement (car es) env))
                                (lambda (value new-env)
                                  (loop (cdr es) new-env value)))))
                        (values '() (void))))))
    ;; eval — maps to seed-evaluate for runtime vau/operative code
    (eval . ,seed-evaluate)
    ;; set! — operative, mutates the binding in the environment alist
    (set! . ,(cons 'operative
                (lambda (env name value-expression)
                  (let ([v (seed-evaluate value-expression env)]
                        [cell (assq name env)])
                    (if cell
                        (begin (set-cdr! cell v) (values '() v))
                        (error 'set! "unbound" name))))))
    ))

;; =========================================================================
;; Driver
;; =========================================================================

;; Full compilation pipeline: source -> L4 -> Chez Scheme code
(define (compile expression)
  (generate-code
    (analyze-binding-time
      (classify
        ((annotate '()) (parse expression))))))

;; Read all S-expression forms from a file.
(define (read-all-forms filename)
  (call-with-input-file filename
    (lambda (port)
      (let loop ([forms '()])
        (let ([form (read port)])
          (if (eof-object? form)
              (reverse forms)
              (loop (cons form forms))))))))

;; Transform top-level forms into nested letrec expressions.
;; Groups consecutive defines into letrec blocks, splitting at non-define forms.
;; User writes sequential defines; compilation uses letrec for correct scoping.
(define (transform-top-level forms)
  (define (wrap-letrec bindings body)
    (if (null? bindings) body
        `(letrec ,(reverse bindings) ,body)))
  (let loop ([fs forms] [bindings '()])
    (cond
      [(null? fs)
       (wrap-letrec bindings '(void))]
      [else
       (let ([form (car fs)])
         (match form
           ;; (define (name params...) body...) -> function definition
           [(define (,name . ,parameters) . ,body)
            (loop (cdr fs)
                  (cons (list name `(lambda ,parameters ,@body)) bindings))]
           ;; (define (names...) expr) -> destructuring binding
           [(define (,names ...) ,expression)
            (let* ([temporary (gensym "values")]
                   [rest (loop (cdr fs) '())]
                   [inner `(let ((,temporary ,expression))
                             (let ,(let idx-loop ([ns names] [index 0] [accumulator '()])
                                     (if (null? ns) (reverse accumulator)
                                         (idx-loop (cdr ns) (+ index 1)
                                           (cons (list (car ns) `(list-ref ,temporary ,index))
                                                 accumulator))))
                               ,rest))])
              (wrap-letrec bindings inner))]
           ;; (define name value) -> simple binding
           [(define ,name ,value)
            (guard (symbol? name))
            (loop (cdr fs) (cons (list name value) bindings))]
           ;; Non-define expression
           [,expression
            (let ([rest (loop (cdr fs) '())])
              (wrap-letrec bindings
                (if (equal? rest '(void))
                    expression
                    `(begin ,expression ,rest))))]))])))

;; Run a source expression through Seed compile + Chez JIT compile.
(define (run expression)
  (let* ([code (compile expression)]
         [result (chez-compile code)])
    result))

;; Run with ground environment (for vau/eval programs).
(define (run-with-environment expression)
  (let* ([code (compile expression)]
         [wrapped `(let ([env ',environment-ground]) ,code)]
         [result (chez-compile wrapped)])
    result))

;; Pretty-print compiled code to stderr.
(define (dump-file filename)
  (let* ([expression (transform-top-level (read-all-forms filename))]
         [code (compile expression)])
    (pretty-print code (current-error-port))))

;; Run a .seed file: compile and execute with ground environment.
(define (run-file filename)
  (collect-request-handler void)
  (time
    (let* ([expression (transform-top-level (read-all-forms filename))]
           [code (compile expression)]
           [wrapped `(let ([env ',environment-ground]) ,code)])
      (chez-compile wrapped))))


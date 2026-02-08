#!r6rs

;; SRFI 241: Match - Portable hygienic pattern matcher
;; Copyright (C) Marc Nieper-Wißkirchen (2021, 2022).  All Rights Reserved.
;;
;; Permission is hereby granted, free of charge, to any person
;; obtaining a copy of this software and associated documentation
;; files (the "Software"), to deal in the Software without
;; restriction, including without limitation the rights to use, copy,
;; modify, merge, publish, distribute, sublicense, and/or sell copies
;; of the Software, and to permit persons to whom the Software is
;; furnished to do so, subject to the following conditions:
;;
;; The above copyright notice and this permission notice shall be
;; included in all copies or substantial portions of the Software.
;;
;; THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
;; EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
;; MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
;; NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
;; BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
;; ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
;; CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
;; SOFTWARE.

(library (match)
  (export
    match
    unquote
    ...
    _
    ->
    guard
    extend-backquote
    define-extended-quasiquote

    ~check-010
    ~check-020
    ~check-030
    ~check-040
    ~check-050
    ~check-060
    ~check-070
    ~check-080
    ~check-090
    ~check-100
    ~check-110
    ~check-120
    ~check-130
    )
  (import
    (except (chezscheme) with-implicit))

  ;;; Helper: with-implicit (needed at expand time)
  (define-syntax with-implicit
    (lambda (x)
      (syntax-case x ()
        [(_ (k x ...) e1 ... e2)
         #'(with-syntax ([x (datum->syntax #'k 'x)] ...)
             e1 ... e2)]
        [_ (syntax-violation 'with-implicit "invalid syntax" x)])))

  ;;; Helper: define/who and define-syntax/who (needed at expand time)
  (define-syntax define/who
    (lambda (x)
      (define parse
        (lambda (x)
          (syntax-case x ()
            [(k (f . u) e1 ... e2)
             (identifier? #'f)
             (values #'k #'f #'((lambda u e1 ... e2)))]
            [(k f e1 ... e2)
             (identifier? #'f)
             (values #'k #'f #'(e1 ... e2))]
            [_ (syntax-violation 'define/who "invalid syntax" x)])))
      (let-values ([(k f e*) (parse x)])
        (with-syntax ([k k] [f f] [(e1 ... e2) e*])
          (with-implicit (k who)
            #'(define f
                (let ([who 'f])
                  e1 ... e2)))))))

  (define-syntax define-syntax/who
    (lambda (x)
      (syntax-case x ()
        [(k n e1 ... e2)
         (identifier? #'n)
         (with-implicit (k who)
           #'(define-syntax n
               (let ([who 'n])
                 e1 ... e2)))])))

  ;;; Helper: define-auxiliary-syntax (needed at expand time)
  (define-syntax/who define-auxiliary-syntax
    (lambda (x)
      (syntax-case x ()
        [(_ name)
         (identifier? #'name)
         #'(define-syntax/who name
             (lambda (x)
               (syntax-violation who "misplaced auxiliary keyword" x)))]
        [_ (syntax-violation who "invalid syntax" x)])))

  ;;; Auxiliary syntax
  (define-auxiliary-syntax ->)

  ;;; Core match implementation
  (define-syntax/who match
    (define-record-type pattern-variable
      (nongenerative) (sealed #t) (opaque #t)
      (fields (mutable identifier) expression level))
    (define-record-type cata-binding
      (nongenerative) (sealed #t) (opaque #t)
      (fields proc-expr value-id* identifier))

    ;; ellipsis? needs to be available at expansion time
    (define ellipsis?
      (lambda (x)
        (and (identifier? x)
             (free-identifier=? x #'(... ...)))))

    (lambda (stx)
      (define make-identifier-hashtable
	(lambda ()
	  (define identifier-hash
	    (lambda (id)
	      (assert (identifier? id))
	      (symbol-hash (syntax->datum id))))
	  (make-hashtable identifier-hash bound-identifier=?)))
      (define pattern-variable-guards
	(lambda (pvars)
	  (define ht (make-identifier-hashtable))
          (fold-left
           (lambda (guards pvar)
             (let ([id (pattern-variable-identifier pvar)])
               (cond
                [(hashtable-ref ht id #f)
                 (with-syntax ([id id]
                               [(new-id) (generate-temporaries #'(id))]
                               [guards guards])
                   (pattern-variable-identifier-set! pvar #'new-id)
                   #'((equal? id new-id) . guards))]
                [else
                 (hashtable-set! ht id #t)
                 guards])))
           '() pvars)))
      (define check-cata-bindings
	(lambda (catas)
	  (define ht (make-identifier-hashtable))
	  (for-each
	   (lambda (cata)
	     (for-each
	      (lambda (id)
		(hashtable-update!
                 ht
		 id
		 (lambda (val)
		   (when val
		     (syntax-violation who "repeated cata variable in match clause" stx id))
		   #t)
		 #f))
	      (cata-binding-value-id* cata)))
	   catas)))
      (define parse-clause
        (lambda (cl)
          (syntax-case cl (guard)
            [(pat (guard guard-expr ...) e1 e2 ...)
             (values #'pat #'(and guard-expr ...) #'(e1 e2 ...))]
            [(pat e1 e2 ...)
             (values #'pat #'#t #'(e1 e2 ...))]
            [_
             (syntax-violation who "ill-formed match clause" stx cl)])))
      (define gen-matcher
        (lambda (expr pat)
          (define ill-formed-match-pattern-violation
            (lambda ()
              (syntax-violation who "ill-formed match pattern" stx pat)))
          (syntax-case pat (-> unquote)
            [,[f -> y ...]
             (for-all identifier? #'(y ...))
             (with-syntax ([(x) (generate-temporaries '(x))])
               (values
                (lambda (k)
                  (k))
                (list (make-pattern-variable #'x expr 0))
                (list (make-cata-binding #'f #'(y ...) #'x))))]
            [,[y ...]
             (for-all identifier? #'(y ...))
             (with-syntax ([(x) (generate-temporaries '(x))])
               (values
                (lambda (k)
                  (k))
                (list (make-pattern-variable #'x expr 0))
                (list (make-cata-binding #'loop #'(y ...) #'x))))]
            [(pat1 ell pat2 ... . ,e)
             (ellipsis? #'ell)
             (gen-ellipsis-matcher expr #'pat1 #'(pat2 ...) #',e)]
            [(pat1 ell pat2 ... . pat3)
             (ellipsis? #'ell)
             (gen-ellipsis-matcher expr #'pat1 #'(pat2 ...) #'pat3)]
            [#(x ...)
             (with-syntax ([(e) (generate-temporaries '(e))])
               (let-values ([(mat pvars catas)
                             (gen-matcher #'e #'(x ...))])
                 (values
                  (lambda (k)
                    #`(if (vector? #,expr)
                          (let ([e (vector->list #,expr)])
                            #,(mat k))
                          (fail)))
                  pvars catas)))]
            [,x
             (identifier? #'x)
             (values
               (lambda (k)
                 (k))
               (if (free-identifier=? #'x #'_)
                   '()
                   (list (make-pattern-variable #'x expr 0)))
               '())]
            [(pat1 . pat2)
             (with-syntax ([(e1 e2) (generate-temporaries '(e1 e2))])
               (let*-values ([(mat1 pvars1 catas1)
                              (gen-matcher #'e1 #'pat1)]
                             [(mat2 pvars2 catas2)
                              (gen-matcher #'e2 #'pat2)])
                 (values
                  (lambda (k)
                    #`(if (pair? #,expr)
                          (let ([e1 (car #,expr)]
                                [e2 (cdr #,expr)])
                            #,(mat1 (lambda () (mat2 k))))
                          (fail)))
                  (append pvars1 pvars2) (append catas1 catas2))))]
            [unquote
             (ill-formed-match-pattern-violation)]
            [_
             (values
              (lambda (k)
                #`(if (equal? #,expr (quote #,pat))
                      #,(k)
                      (fail)))
              '() '())])))
      (define gen-ellipsis-matcher
        (lambda (expr pat1 pat2* pat3)
          (with-syntax ([(e1 e2) (generate-temporaries '(e1 e2))])
            (let*-values ([(mat1 pvars1 catas1)
                           (gen-map #'e1 pat1)]
                          [(mat2 pvars2 catas2)
                           (gen-matcher* #'e2 (append pat2* pat3))])
              (values
               (lambda (k)
                 #`(split
                    #,expr
                    #,(length pat2*)
                    (lambda (e1 e2)
                      #,(mat1 (lambda () (mat2 k))))
                    fail))
               (append pvars1 pvars2)
               (append catas1 catas2))))))
      (define gen-matcher*
        (lambda (expr pat*)
          (syntax-case pat* (unquote)
            [()
             (values
              (lambda (k)
                #`(if (null? #,expr)
                      #,(k)
                      (fail)))
              '() '())]
            [,x
             (gen-matcher expr pat*)]
            [(pat . pat*)
             (with-syntax ([(e1 e2) (generate-temporaries '(e1 e2))])
               (let*-values ([(mat1 pvars1 catas1)
                              (gen-matcher #'e1 #'pat)]
                             [(mat2 pvars2 catas2)
                              (gen-matcher* #'e2 #'pat*)])
                 (values
                  (lambda (k)
                    #`(let ([e1 (car #,expr)]
                            [e2 (cdr #,expr)])
                        #,(mat1
                           (lambda ()
                             (mat2 k)))))
                  (append pvars1 pvars2)
                  (append catas1 catas2))))]
            [_
             (gen-matcher expr pat*)])))
      (define gen-map
        (lambda (expr pat)
          (with-syntax ([(e1 e2 f) (generate-temporaries '(e1 e2 f))])
            (let-values ([(mat ipvars catas)
                          (gen-matcher #'e1 pat)])
              (with-syntax ([(u ...)
                             (generate-temporaries ipvars)]
                            [(v ...)
                             (map pattern-variable-expression ipvars)])
                (values
                 (lambda (k)
                   #`(let f ([e2 (reverse #,expr)]
                             [u '()] ...)
                       (if (null? e2)
                           #,(k)
                           (let ([e1 (car e2)])
                             #,(mat (lambda ()
                                      #`(f (cdr e2) (cons v u) ...)))))))
                 (map
                  (lambda (id pvar)
                    (make-pattern-variable
                     (pattern-variable-identifier pvar)
                     id
                     (fx+ (pattern-variable-level pvar) 1)))
                  #'(u ...) ipvars)
                 catas))))))
      (define gen-map-values
        (lambda (proc-expr y* e n)
          (let f ([n n])
            (if (fxzero? n)
                #`(#,proc-expr #,e)
                (with-syntax ([(tmps ...)
                               (generate-temporaries y*)]
                              [(tmp ...)
                               (generate-temporaries y*)]
                              [e e])
                  #`(let f ([e* (reverse e)]
                            [tmps '()] ...)
                      (if (null? e*)
                          (values tmps ...)
                          (let ([e (car e*)]
                                [e* (cdr e*)])
                            (let-values ([(tmp ...)
                                          #,(f (fx- n 1))])
                              (f e* (cons tmp tmps) ...))))))))))
      (define gen-clause
        (lambda (k cl)
          (let*-values ([(pat guard-expr body)
                         (parse-clause cl)]
                        [(matcher pvars catas)
                         (gen-matcher #'e pat)])
            (define pvar-guards (pattern-variable-guards pvars))
	    (check-cata-bindings catas)
            (with-syntax ([(x ...)
                           (map pattern-variable-identifier pvars)]
                          [(u ...)
                           (map pattern-variable-expression pvars)]
                          [(f ...)
                           (map cata-binding-proc-expr catas)]
                          [((y ...) ...)
                           (map cata-binding-value-id* catas)]
                          [(z ...)
                           (map cata-binding-identifier catas)]
                          [(tmp ...)
                           (generate-temporaries catas)])
              (with-syntax ([(e ...)
                             (map
                              (lambda (tmp y* z)
                                (let ([n
                                       (exists
                                        (lambda (pvar)
                                          (let ([x (pattern-variable-identifier pvar)])
                                            (and (bound-identifier=? x z)
                                                 (pattern-variable-level pvar))))
                                        pvars)])
                                  (gen-map-values tmp y* z n)))
                              #'(tmp ...) #'((y ...) ...) #'(z ...))])
                (matcher
                 (lambda ()
                   #`(let ([x u] ...)
                       (if (and #,@pvar-guards (extend-backquote #,k #,guard-expr))
                           (let ([tmp f] ...)
                             (let-values ([(y ...) e] ...)
                               (extend-backquote #,k
                                 #,@body)))
                           (fail))))))))))
      (define gen-match
        (lambda (k cl*)
          (fold-right
           (lambda (cl rest)
             #`(let ([fail (lambda () #,rest)])
                 #,(gen-clause k cl)))
           #'(assertion-violation 'match "expression does not match" e)
           cl*)))

      (syntax-case stx ()
        [(k expr cl ...)
         #`(let loop ([e expr])
             #,(gen-match #'k #'(cl ...)))])))

  ;;; extend-backquote
  (define-syntax/who extend-backquote
    (lambda (x)
      (syntax-case x ()
        [(_ here e1 ... e2)
         (identifier? #'here)
         (with-implicit (here quasiquote)
           #'(let-syntax ([quasiquote quasiquote-transformer])
               e1 ... e2))]
        [_ (syntax-violation who "invalid syntax" x)])))

  ;;; define-extended-quasiquote
  (define-syntax/who define-extended-quasiquote
    (lambda (x)
      (syntax-case x ()
        [(_ qq)
         (identifier? #'qq)
         #'(define-syntax qq quasiquote-transformer)])))

  ;;; quasiquote-transformer
  (meta define quasiquote-transformer
    (lambda (stx)
      (define who 'quasiquote)
      (define-record-type template-variable
        (nongenerative) (sealed #t) (opaque #t)
        (fields identifier expression))

      ;; ellipsis? needs to be available at expansion time
      (define ellipsis?
        (lambda (x)
          (and (identifier? x)
               (free-identifier=? x #'(... ...)))))

      (define quasiquote-syntax-violation
        (lambda (subform msg)
          (syntax-violation 'quasiquote msg stx subform)))
      (define gen-output
        (lambda (k tmpl lvl ell?)
          (define quasiquote?
            (lambda (x)
              (and (identifier? x) (free-identifier=? x k))))
          (define gen-ellipsis
            (lambda (tmpl* out* vars* depth tmpl2)
              (let f ([depth depth] [tmpl2 tmpl2])
                (syntax-case tmpl2 ()
                  [(ell . tmpl2)
                   (ell? #'ell)
                   (f (fx+ depth 1) #'tmpl2)]
                  [tmpl2
                   (let-values ([(out2 vars2)
                                 (gen-output k #'tmpl2 0 ell?)])
		     (for-each
		      (lambda (tmpl vars)
			(when (or (not vars) (null? vars))
			  (quasiquote-syntax-violation tmpl
                            "no substitutions to repeat here")))
		      tmpl* vars*)
                     (with-syntax ([((tmp** ...) ...)
                                    (map (lambda (vars)
                                           (map template-variable-identifier vars))
					 vars*)]
				   [(out1 ...) out*])
                       (values #`(append (append-n-map #,depth
						       (lambda (tmp** ...)
							 out1)
						       tmp** ...)
					 ...
                                         #,out2)
                               (append (apply append vars*)
                                       (or vars2 '())))))]))))
	  (define gen-unquote*
	    (lambda (expr*)
              (with-syntax ([(tmp* ...) (generate-temporaries expr*)])
		(values #'(tmp* ...)
			(map (lambda (tmp expr)
			       (list (make-template-variable tmp expr)))
			     #'(tmp* ...) expr*)))))
	  (syntax-case tmpl (unquote unquote-splicing) ;qq is K.
            ;; (<ellipsis> <template>)
            [(ell tmpl)
             (ell? #'ell)
             (let-values ([(out vars)
                           (gen-output k #'tmpl lvl (lambda (x) #f))])
               (values out (or vars '())))]
            ;; (quasiquote <template>)
            [`tmpl
             (quasiquote? #'quasiquote)
             (let-values ([(out vars) (gen-output k #'tmpl (fx+ lvl 1) ell?)])
               (if (not vars)
                   (values #'`tmpl
                           #f)
                   (values #`(list 'quasiquote #,out)
                           vars)))]
            ;; (unquote <template>)
            [,expr
             (fxzero? lvl)
             (with-syntax ([(tmp) (generate-temporaries '(tmp))])
               (values #'tmp (list (make-template-variable #'tmp #'expr))))]
            [,tmpl
             (let-values ([(out vars)
                           (gen-output k #'tmpl (fx- lvl 1) ell?)])
               (if (not vars)
                   (values #'(quote ,tmpl) #f)
                   (values #`(list 'unquote #,out) vars)))]
            ;; ((unquote-splicing <template> ...) <ellipsis> . <template>)
	    [((unquote-splicing expr ...) ell . tmpl2)
	     (and (fxzero? lvl) (ell? #'ell))
             (let-values ([(out* vars*)
			   (gen-unquote* #'(expr ...))])
	       (gen-ellipsis #'(expr ...) out* vars* 1 #'tmpl2))]
            ;; (<template> <ellipsis> . <template>)
	    [((unquote expr ...) ell . tmpl2)
	     (and (fxzero? lvl) (ell? #'ell))
             (let-values ([(out* vars*)
			   (gen-unquote* #'(expr ...))])
	       (gen-ellipsis #'(expr ...) out* vars* 0 #'tmpl2))]
            [(tmpl1 ell . tmpl2)
             (and (fxzero? lvl) (ell? #'ell))
             (let-values ([(out1 vars1)
                           (gen-output k #'tmpl1 0 ell?)])
               (gen-ellipsis #'(tmpl1) (list out1) (list vars1) 0 #'tmpl2))]
            ;; ((unquote <template> ...) . <template>)
            [((unquote tmpl1 ...) . tmpl2)
             (let-values ([(out vars)
                           (gen-output k #'tmpl2 lvl ell?)])
               (if (fxzero? lvl)
                   (with-syntax ([(tmp ...)
                                  (generate-temporaries #'(tmpl1 ...))])
                     (values #`(cons* tmp ... #,out)
                             (append
                              (map make-template-variable #'(tmp ...) #'(tmpl1 ...))
                              (or vars '()))))
                   (let-values ([(out* vars*)
                                 (gen-output* k #'(tmpl1 ...) (fx- lvl 1) ell?)])
                     (if (and (not vars)
                              (not vars*))
                         (values #'(quote ((unquote-splicing tmpl1 ...) . tmpl2))
                                 #f)
                         (values #`(cons (list 'unquote #,@out*) #,out)
                                 (append (or vars* '())
                                         (or vars '())))))))]
            ;; ((unquote-splicing <template> ...) . <template>)
            [((unquote-splicing tmpl1 ...) . tmpl2)
             ;; TODO: Use gen-ellipsis.
             (let-values ([(out vars)
                           (gen-output k #'tmpl2 lvl ell?)])
               (if (fxzero? lvl)
                   (with-syntax ([(tmp ...)
                                  (generate-temporaries #'(tmpl1 ...))])
                     (values #`(append tmp ... #,out)
                             (append
                              (map make-template-variable #'(tmp ...) #'(tmpl1 ...))
                              (or vars '()))))
                   (let-values ([(out* vars*)
                                 (gen-output* k #'(tmpl1 ...) (fx- lvl 1) ell?)])
                     (if (and (not vars)
                              (not vars*))
                         (values #'(quote ((unquote-splicing tmpl1 ...) . tmpl2))
                                 '())
                         (values #`(cons (list 'unquote-splicing #,@out*) #,out)
                                 (append (or vars* '())
                                         (or vars '())))))))]
            ;; (<element> . <element>)
            [(el1 . el2)
             (let-values ([(out1 vars1)
                           (gen-output k #'el1 lvl ell?)]
                          [(out2 vars2)
                           (gen-output k #'el2 lvl ell?)])
               (if (and (not vars1)
                        (not vars2))
                   (values #'(quote (el1 . el2))
                           '())
                   (values #`(cons #,out1 #,out2)
                           (append (or vars1 '()) (or vars2 '())))))]
            ;; #(<element> ...)
            [#(el ...)
             (let-values ([(out vars)
                           (gen-output k #'(el ...) lvl ell?)])
               (if (not vars)
                   (values #'(quote #(el ...)) #f)
                   (values #`(list->vector #,out) vars)))]
            ;; <constant>
            [constant
             (values #'(quote constant) #f)])))
      (define gen-output*
        (lambda (k tmpl* lvl ell?)
          (let f ([tmpl* tmpl*] [out* '()] [vars* #f])
            (if (null? tmpl*)
                (values (reverse out*) vars*)
                (let ([tmpl (car tmpl*)]
                      [tmpl* (cdr tmpl*)])
                  (let-values ([(out vars) (gen-output k tmpl lvl ell?)])
                    (f tmpl* (cons out out*)
                       (if vars
                           (append vars (or vars* '()))
                           vars*))))))))
      (syntax-case stx ()
        [(k tmpl)
         (let-values ([(out vars)
                       (gen-output #'k #'tmpl 0
                                   ellipsis?)])
           (let ([vars (or vars '())])
             (with-syntax ([(x ...) (map template-variable-identifier vars)]
                           [(e ...) (map template-variable-expression vars)])
               #`(let ([x e] ...)
                   #,out))))]
        [_
         (syntax-violation who "invalid syntax" stx)])))

  ;;; Runtime support procedures
  (define split
    (lambda (obj k succ fail)
      (let ([n (length+ obj)])
        (if (and n
                 (fx<=? k n))
            (call-with-values
                (lambda ()
                  (split-at obj (fx- n k)))
              succ)
            (fail)))))

  (define length+
    (lambda (x)
      (let f ([x x] [y x] [n 0])
        (if (pair? x)
            (let ([x (cdr x)]
                  [n (fx+ n 1)])
              (if (pair? x)
                  (let ([x (cdr x)]
                        [y (cdr y)]
                        [n (fx+ n 1)])
                    (and (not (eq? x y))
                         (f x y n)))
                  n))
            n))))

  (define/who split-at
    (lambda (ls k)
      (let f ([ls ls] [k k])
        (cond
         [(fxzero? k)
          (values '() ls)]
         [(pair? ls)
          (let-values ([(ls1 ls2) (f (cdr ls) (fx- k 1))])
            (values (cons (car ls) ls1) ls2))]
         [else (assert #f)]))))

  (define append-n-map
    (lambda (n proc . arg*)
      (let f ([n n] [arg* arg*])
        (if (fxzero? n)
            (apply map proc arg*)
            (let ([n (fx- n 1)])
              (apply append
                     (apply map
                            (lambda arg*
                              (f n arg*))
                            arg*)))))))
  
  (define ~check-010
    (lambda ()
      (assert (equal? 3
		      (match '(a 17 37)
		        [(a ,x) 1]
		        [(b ,x ,y) 2]
		        [(a ,x ,y) 3])))))

  (define ~check-020
    (lambda ()
      (assert (equal? 629
		      (match '(a 17 37)
		        [(a ,x) (- x)]
		        [(b ,x ,y) (+ x y)]
		        [(a ,x ,y) (* x y)])))
      (assert (equal? '(17 37)
		      (match '(a 17 37) [(a ,x* ...) x*])))
      (assert (equal? '(a stitch in time saves nine)
		      (match '(say (a time) (stitch saves) (in nine))
		        [(say (,x* ,y*) ...) (append x* y*)])))
      (assert (equal? '((a e h j) ((b c d) (f g) (i) ()))
		      (match '((a b c d) (e f g) (h i) (j))
		        [((,x* ,y** ...) ...)
		         (list x* y**)])))))

  (define ~check-030
    (lambda ()
      (define simple-eval
        (lambda (x)
          (match x
            [,i (guard (integer? i)) i]
            [(+ ,[x*] ...) (apply + x*)]
            [(* ,[x*] ...) (apply * x*)]
            [(- ,[x] ,[y]) (- x y)]
            [(/ ,[x] ,[y]) (/ x y)]
            [,x (assertion-violation 'simple-eval "invalid expression" x)])))
      (assert (equal? 6
		      (simple-eval '(+ 1 2 3))))
      (assert (equal? 4
		      (simple-eval '(+ (- 0 1) (+ 2 3)))))
      (assert (guard (c
		      [(assertion-violation? c) #t])
	        (simple-eval '(- 1 2 3))))))

  (define ~check-040
    (lambda ()
      (define translate
        (lambda (x)
          (match x
            [(let ((,var* ,expr*) ...) ,body ,body* ...)
             `((lambda ,var* ,body ,body* ...) ,expr* ...)]
            [,x (assertion-violation 'translate "invalid expression" x)])))
      (assert (equal? '((lambda (x y) (+ x y)) 3 4)
		      (translate '(let ((x 3) (y 4)) (+ x y)))))))

  (define ~check-050
    (lambda ()
      (define (f x)
        (match x
          [((,a ...) (,b ...)) `((,a . ,b) ...)]))
      (assert (equal? '((1 . a) (2 . b) (3 . c))
		      (f '((1 2 3) (a b c)))))
      (assert (guard (c
		      [(assertion-violation? c) #t])
	        (f '((1 2 3) (a b)))))))

  (define ~check-060
    (lambda ()
      (define (g x)
        (match x
          [(,a ,b ...) `((,a ,b) ...)]))
      (assert (guard (c
		      [(assertion-violation? c) #t])
	        (g '(1 2 3 4))))))

  (define ~check-070
    (lambda ()
      (define (h x)
        (match x
          [(let ([,x ,e1 ...] ...) ,b1 ,b2 ...)
           `((lambda (,x ...) ,b1 ,b2 ...)
             (begin ,e1 ...) ...)]))
      (assert (equal? '((lambda (x y) (list x y))
		        (begin (write 'one) 3)
		        (begin (write 'two) 4))
		      (h '(let ((x (write 'one) 3) (y (write 'two) 4)) (list x y)))))))

  (define ~check-080
    (lambda ()
      (define (k x)
        (match x
          [(foo (,x ...) ...)
           `(list (car ,x) ... ...)]))
      (assert (equal? '(list (car a) (car b) (car c) (car d) (car e) (car f) (car g))
		      (k '(foo (a) (b c d e) () (f g)))))))

  (define ~check-090
    (lambda ()
      (define parse1
        (lambda (x)
          (define Prog
            (lambda (x)
              (match x
                [(program ,[Stmt -> s*] ... ,[Expr -> e])
                 `(begin ,s* ... ,e)]
                [,x (assertion-violation 'parse "invalid program" x)])))
          (define Stmt
            (lambda (x)
              (match x
                [(if ,[Expr -> e] ,[Stmt -> s1] ,[Stmt -> s2])
                 `(if ,e ,s1 ,s2)]
                [(set! ,v ,[Expr -> e])
                 (guard (symbol? v))
                 `(set! ,v ,e)]
                [,x (assertion-violation 'parse "invalid statement" x)])))
          (define Expr
            (lambda (x)
              (match x
                [,v (guard (symbol? v)) v]
                [,n (guard (integer? n)) n]
                [(if ,[e1] ,[e2] ,[e3])
                 `(if ,e1 ,e2 ,e3)]
                [(,[rator] ,[rand*] ...) `(,rator ,rand* ...)]
                [,x (assertion-violation 'parse "invalid expression" x)])))
          (Prog x)))
      (assert (equal? '(begin (set! x 3) (+ x 4))
		      (parse1 '(program (set! x 3) (+ x 4)))))))

  (define ~check-100
    (lambda ()
      (define parse2
        (lambda (x)
          (define Prog
            (lambda (x)
              (match x
                [(program ,[Stmt -> s*] ... ,[(Expr '()) -> e])
                 `(begin ,s* ... ,e)]
                [,x (assertion-violation 'parse "invalid program" x)])))
          (define Stmt
            (lambda (x)
              (match x
                [(if ,[(Expr '()) -> e] ,[Stmt -> s1] ,[Stmt -> s2])
                 `(if ,e ,s1 ,s2)]
                [(set! ,v ,[(Expr '()) -> e])
                 (guard (symbol? v))
                 `(set! ,v ,e)]
                [,x (assertion-violation 'parse "invalid statement" x)])))
          (define Expr
            (lambda (env)
              (lambda (x)
                (match x
                  [,v (guard (symbol? v)) v]
                  [,n (guard (integer? n)) n]
                  [(if ,[e1] ,[e2] ,[e3])
                   (guard (not (memq 'if env)))
                   `(if ,e1 ,e2 ,e3)]
                  [(let ([,v ,[e]]) ,[(Expr (cons v env)) -> body])
                   (guard (not (memq 'let env)) (symbol? v))
                   `(let ([,v ,e]) ,body)]
                  [(,[rator] ,[rand*] ...)
                   `(call ,rator ,rand* ...)]
                  [,x (assertion-violation 'parse "invalid expression" x)]))))
          (Prog x)))
      (assert (equal? '(begin
		         (let ([if (if x list values)])
		           (call if 1 2 3)))
		      (parse2
		       '(program
		            (let ([if (if x list values)])
		              (if 1 2 3))))))))

  (define ~check-110
    (lambda ()
      (define split
        (lambda (ls)
          (match ls
            [() (values '() '())]
            [(,x) (values `(,x) '())]
            [(,x ,y . ,[odds evens])
             (values (cons x odds)
                     (cons y evens))])))
      (assert (equal? '((a c e) (b d f))
		      (call-with-values
		          (lambda ()
		            (split '(a b c d e f)))
		        list)))))

  (define ~check-120
    (lambda ()
      (assert (match 'a
                [(,x) #f]
                [,_ #t]))
      (assert (match 'else
                [else #t]))
      (assert (guard (c [(assertion-violation? c) #t])
                (match 'whatever
                  [else #f])))))

  (define ~check-130
    (lambda ()
      ;; Multiple wildcards in a pattern
      (assert (equal? 'matched
                (match '(1 2 3)
                  [(,_ ,_ ,_) 'matched])))
      ;; Wildcards with captured variables
      (assert (equal? '(1 3)
                (match '(1 2 3)
                  [(,x ,_ ,y) (list x y)])))
      ;; Wildcard with ellipsis - match rest
      (assert (equal? 1
                (match '(1 2 3 4 5)
                  [(,x ,_ ...) x])))
      ;; Wildcard with ellipsis - match last
      (assert (equal? 5
                (match '(1 2 3 4 5)
                  [(,_ ... ,x) x])))
      ;; Multiple wildcards with ellipsis in between
      (assert (equal? '(1 5)
                (match '(1 2 3 4 5)
                  [(,x ,_ ... ,y) (list x y)])))
      ;; Wildcard ellipsis matching empty
      (assert (equal? 'empty
                (match '()
                  [(,_ ...) 'empty])))
      ;; Wildcard ellipsis matching single element
      (assert (equal? 'one
                (match '(x)
                  [(,_ ...) 'one])))
      ;; Wildcard ellipsis matching many elements
      (assert (equal? 'many
                (match '(a b c d e)
                  [(,_ ...) 'many])))
      ;; Named ellipsis with wildcards around
      (assert (equal? '(2 3 4)
                (match '(1 2 3 4 5)
                  [(,_ ,x* ... ,_) x*])))
      ;; Multiple wildcard groups with ellipsis
      (assert (equal? '((1 2) (5 6))
                (match '(1 2 3 4 5 6)
                  [(,a ,b ,_ ... ,c ,d) (list (list a b) (list c d))])))
      ;; Wildcards in vector with ellipsis-like repetition
      (assert (equal? 2
                (match '#(1 2 3)
                  [#(,_ ,x ,_) x])))
      ;; Nested wildcards with ellipsis
      (assert (equal? '(1 3)
                (match '((1 2) (3 4))
                  [((,a ,_) (,b ,_)) (list a b)])))
      ;; Wildcard in cons with ellipsis
      (assert (equal? '(2 3)
                (match '(1 2 3)
                  [(,_ . ,rest) rest])))
      ;; Multiple wildcards then ellipsis capture
      (assert (equal? '(3 4 5)
                (match '(1 2 3 4 5)
                  [(,_ ,_ ,rest* ...) rest*])))
      ;; Ellipsis capture then wildcards
      (assert (equal? '(1 2 3)
                (match '(1 2 3 4 5)
                  [(,first* ... ,_ ,_) first*])))
      ;; Complex: wildcards, capture, ellipsis, capture, wildcards
      (assert (equal? '(2 (4 5) 7)
                (match '(1 2 3 4 5 6 7 8)
                  [(,_ ,a ,_ ,mid* ... ,_ ,b ,_) (list a mid* b)])))))

  )

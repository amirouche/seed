#!r6rs

;; Copyright (C) Marc Nieper-Wißkirchen (2021).  All Rights Reserved.

;; Permission is hereby granted, free of charge, to any person
;; obtaining a copy of this software and associated documentation
;; files (the "Software"), to deal in the Software without
;; restriction, including without limitation the rights to use, copy,
;; modify, merge, publish, distribute, sublicense, and/or sell copies
;; of the Software, and to permit persons to whom the Software is
;; furnished to do so, subject to the following conditions:

;; The above copyright notice and this permission notice shall be
;; included in all copies or substantial portions of the Software.

;; THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
;; EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
;; MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
;; NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
;; BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
;; ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
;; CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
;; SOFTWARE.

(import (rnrs)
        (srfi :241 match))

;;; Examples from R. Kent Dybvig's "Using Match"

(assert (equal? 3
		(match '(a 17 37)
		  [(a ,x) 1]
		  [(b ,x ,y) 2]
		  [(a ,x ,y) 3])))

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
		   (list x* y**)])))

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
	  (simple-eval '(- 1 2 3))))

(define translate
  (lambda (x)
    (match x
      [(let ((,var* ,expr*) ...) ,body ,body* ...)
       `((lambda ,var* ,body ,body* ...) ,expr* ...)]
      [,x (assertion-violation 'translate "invalid expression" x)])))

(assert (equal? '((lambda (x y) (+ x y)) 3 4)
		(translate '(let ((x 3) (y 4)) (+ x y)))))

(define (f x)
  (match x
    [((,a ...) (,b ...)) `((,a . ,b) ...)]))

(assert (equal? '((1 . a) (2 . b) (3 . c))
		(f '((1 2 3) (a b c)))))

(assert (guard (c
		[(assertion-violation? c) #t])
	  (f '((1 2 3) (a b)))))

(define (g x)
  (match x
    [(,a ,b ...) `((,a ,b) ...)]))

(assert (guard (c
		[(assertion-violation? c) #t])
	  (g '(1 2 3 4))))

(define (h x)
  (match x
    [(let ([,x ,e1 ...] ...) ,b1 ,b2 ...)
     `((lambda (,x ...) ,b1 ,b2 ...)
       (begin ,e1 ...) ...)]))

(assert (equal? '((lambda (x y) (list x y))
		  (begin (write 'one) 3)
		  (begin (write 'two) 4))
		(h '(let ((x (write 'one) 3) (y (write 'two) 4)) (list x y)))))

(define (k x)
  (match x
    [(foo (,x ...) ...)
     `(list (car ,x) ... ...)]))

(assert (equal? '(list (car a) (car b) (car c) (car d) (car e) (car f) (car g))
		(k '(foo (a) (b c d e) () (f g)))))

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
		(parse1 '(program (set! x 3) (+ x 4)))))

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
			(if 1 2 3))))))

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
		  list)))

;;; Extra tests

(assert (match 'a
          [(,x) #f]
          [,_ #t]))

(assert (match 'else
          [else #t]))

(assert (guard (c [(assertion-violation? c) #t])
          (match 'whatever
            [else #f])))

;; Local Variables:
;; mode: scheme
;; End:

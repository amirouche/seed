#!r6rs

;; Copyright (C) Marc Nieper-Wißkirchen (2022).  All Rights Reserved.

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

(library (srfi :241 define-who)
  (export
    define/who
    define-syntax/who)
  (import
    (rnrs)
    (srfi :241 with-implicit))

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
                 e1 ... e2)))]))))

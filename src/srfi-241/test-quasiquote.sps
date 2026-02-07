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

(import (except (rnrs) quasiquote)
        (srfi :241 match quasiquote))

(assert (equal? '(list 3 4)
                `(list ,(+ 1 2) 4)))

(assert (equal? '(a 3 4 5 6 b)
                `(a ,(+ 1 2) ,@(map abs '(4 -5 6)) b)))

(assert (equal? '(a 3 4 5 6 b)
                `(a ,(+ 1 2) ,(map abs '(4 -5 6)) ... b)))

(assert (equal? '((1 . a) (2 . b) (3 . c))
                `((,'(1 2 3) . ,'(a b c)) ...)))

(assert (equal? '(((a x) (a 1)) ((a x) (a 2)) ((a x) (a 3)))
                `(((a ,'((x 1) (x 2) (x 3))) ...) ...)))

(assert (equal? '((a x) (a 1) (a x) (a 2) (a x) (a 3))
                `((a ,'((x 1) (x 2) (x 3))) ... ...)))

(assert (equal? '((a x 1) (a x 2) (a x 3))
                `((a ,@'((x 1) (x 2) (x 3))) ...)))

(assert (equal? '((1 2 3) ...)
                `(... (,'(1 2 3) ...))))

(assert (equal? '(a `(b ,(list 1 2) ... ,(foo 1 3 d) e) f)
                `(a `(b ,(list 1 2) ... ,(foo ,(list 1 3) ... d) e) f)))

(assert (equal? '(a 3)
                `((unquote 'a (+ 1 2)))))

(assert (equal? '(a b c d e f)
                `((unquote-splicing '(a b c) '(d e f)))))

(assert (equal? '((a x 1) (a x 2) (a x 3))
                `((a ,'((x 1) (x 2) (x 3)) ...) ...)))

(assert (equal? '(1 2 3 4 5 6)
		`((unquote (list 1 2 3) (list 4 5 6)) ...)))

(assert (equal? '(x 1 x 2 x 3)
		`(,@'((x 1) (x 2) (x 3)) ...)))

;; Local Variables:
;; mode: scheme
;; End:

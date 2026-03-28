;;; walrus.scm -- Python-style walrus operator (:=) via syntax-rules
;;;
;;; Chez Scheme equivalent of walrus.seed2.scm.
;;;
;;; (while:= var := expr body ...)
;;;
;;; Compare with Seed2:
;;;   Seed2: vau + (define env var val) -- runtime, matches := token
;;;   Chez:  syntax-rules with literal := -- compile-time expansion

(define-syntax while:=
  (syntax-rules (:=)
    [(_ var := expr body ...)
     (let loop ()
       (let ([var expr])
         (when var
           body ...
           (loop))))]))

;; ── File-read simulation (same as walrus.seed2.scm) ──

(define make-file (lambda (chunks) (list chunks)))
(define file-read
  (lambda (f)
    (let ((chunks (car f)))
      (if (null? chunks)
          #f
          (let ((chunk (car chunks)))
            (set-car! f (cdr chunks))
            chunk)))))

;; ── Examples (same as walrus.seed2.scm) ──

(display "--- walrus operator (:=) examples ---")
(newline)

(display "chunks: ")
(let ((f (make-file '("hello" " " "world" "!"))))
  (while:= chunk := (file-read f)
    (display chunk)))
(newline)

(display "matrix: ")
(let ((rows (make-file (list (make-file '(1 2 3))
                             (make-file '(4 5 6))
                             (make-file '(7 8 9))))))
  (while:= row := (file-read rows)
    (while:= cell := (file-read row)
      (display cell) (display " "))))
(newline)

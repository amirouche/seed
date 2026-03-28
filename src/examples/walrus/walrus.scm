;;; walrus.scm — Python-style walrus operator (:=) via syntax-rules
;;;
;;; Chez Scheme equivalent of walrus.seed2.
;;;
;;; (while:= var := expr body ...)
;;;
;;; Compare with Seed2:
;;;   Seed2: vau + (define env var val) — runtime, matches := token
;;;   Chez:  syntax-rules with literal := — compile-time expansion

(define-syntax while:=
  (syntax-rules (:=)
    [(_ var := expr body ...)
     (let loop ()
       (let ([var expr])
         (when var
           body ...
           (loop))))]))

;; ── File-read simulation (same as walrus.seed2) ──

(define make-file (lambda (chunks) (list chunks)))
(define file-read
  (lambda (f)
    (let ((chunks (car f)))
      (if (null? chunks)
          #f
          (let ((chunk (car chunks)))
            (set-car! f (cdr chunks))
            chunk)))))

;; ── Examples (same as walrus.seed2) ──

(display "--- walrus operator (:=) examples ---")
(newline)

(display "chunks: ")
(let ((f (make-file '("hello" " " "world" "!"))))
  (while:= chunk := (file-read f)
    (display chunk)))
(newline)

(display "sum: ")
(let ((f (make-file '(10 20 30 40))))
  (let ((total 0))
    (while:= n := (file-read f)
      (set! total (+ total n)))
    (display total)))
(newline)

(display "found: ")
(let ((f (make-file '(1 3 5 8 11 13))))
  (let ((found #f))
    (while:= x := (file-read f)
      (when (even? x)
        (unless found (set! found x))))
    (display found)))
(newline)

(display "matrix: ")
(let ((rows (make-file (list (make-file '(1 2 3))
                             (make-file '(4 5 6))
                             (make-file '(7 8 9))))))
  (while:= row := (file-read rows)
    (while:= cell := (file-read row)
      (display cell) (display " "))))
(newline)

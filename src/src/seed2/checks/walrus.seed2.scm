;;; walrus.seed2 -- Python-style walrus operator (:=) via vau
;;;
;;; (while var := expr body ...)
;;;
;;; Evaluates expr each iteration.  If truthy, binds the result to
;;; var in the caller's scope and evaluates body.  Repeats until
;;; expr returns #f.
;;;
;;; Reproduces Python's:
;;;   while chunk := file.read(1024):
;;;       process(chunk)
;;;
;;; In Python this required PEP 572 and a new operator.
;;; In Seed2 it's a vau that pattern-matches the := token.
;;;
;;; NOTE: body forms are eval'd at runtime via seed-eval, so they
;;; can only reference variables in the env alist (operative-defined
;;; bindings, ground-env).  Caller-scope let-bound variables are
;;; Chez locals and not visible -- see WALRUS-TODO.md.

(define while:=
  (vau (var sep expr . body) env
    (if (not (eq? sep ':=))
        (error 'while:= "expected :=" sep)
        (let loop ()
          (let ((val (eval expr env)))
            (if val
              (begin
                (define env var val)
                (for-each (lambda (e) (eval e env)) body)
                (loop))
              (void)))))))

;; ── File-read simulation ──
;; A "file" is a box holding a list of chunks.
;; (file-open chunks) -> file
;; (file-read file)   -> next chunk or #f

(define make-file (lambda (chunks) (list chunks)))
(define file-read
  (lambda (f)
    (let ((chunks (car f)))
      (if (null? chunks)
          #f
          (let ((chunk (car chunks)))
            (set-car! f (cdr chunks))
            chunk)))))

;; ── Examples ──

(display "--- walrus operator (:=) examples ---")
(newline)

;; 1. Basic: iterate over file chunks
(display "chunks: ")
(let ((f (make-file '("hello" " " "world" "!"))))
  (while:= chunk := (file-read f)
    (display chunk)))
(newline)

;; 2. Nested walrus: matrix rows then cells
(display "matrix: ")
(let ((rows (make-file (list (make-file '(1 2 3))
                             (make-file '(4 5 6))
                             (make-file '(7 8 9))))))
  (while:= row := (file-read rows)
    (while:= cell := (file-read row)
      (display cell) (display " "))))
(newline)

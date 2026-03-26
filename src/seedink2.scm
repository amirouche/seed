#!/usr/bin/env scheme --script
;;;
;;; seedink2.scm — Seed2 Compiler Command-Line Interface
;;;
;;; Usage:
;;;   scheme --script seedink2.scm <file.seed>      Run a .seed file
;;;   scheme --script seedink2.scm --dump <file>    Dump compiled code
;;;   scheme --script seedink2.scm                  Start REPL
;;;

(import (chezscheme) (seed2))

;; =========================================================================
;; Command-line driver
;; =========================================================================

(define (main args)
  (cond
    ;; Dump compiled code
    [(and (>= (length args) 3) (string=? (cadr args) "--dump"))
     (dump-file (caddr args))]

    ;; Run a .seed file
    [(>= (length args) 2)
     (run-file (cadr args))]

    ;; Start REPL
    [else
     (seed-repl)]))

;; =========================================================================
;; REPL
;; =========================================================================

(define (seed-repl)
  (display "Seed2 REPL (Ctrl-D to exit)\n")
  (display "  Commands: (parse expr), (compile expr), (run expr), etc.\n")
  (display "  Ground env available as 'ground-env'\n\n")
  (let loop ()
    (display "seed2> ")
    (flush-output-port (current-output-port))
    (let ([expr (read)])
      (unless (eof-object? expr)
        (guard (ex
                [else
                 (display "Error: ")
                 (display (if (condition? ex)
                              (condition-message ex)
                              (format "~a" ex)))
                 (newline)])
          (let ([result (eval expr)])
            (unless (eq? result (void))
              (write result)
              (newline))))
        (loop)))))

;; Execute main
(main (command-line))

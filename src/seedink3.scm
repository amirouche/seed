#!/usr/bin/env scheme --script
;;;
;;; seedink3.scm — Seed3 Compiler Command-Line Interface
;;;
;;; Usage:
;;;   scheme --script seedink3.scm <file.seed>      Run a .seed file
;;;   scheme --script seedink3.scm --dump <file>    Dump compiled code
;;;

(import (chezscheme) (seed3))

;; =========================================================================
;; Command-line driver
;; =========================================================================

(define (main args)
  (cond
    ;; Dump compiled code
    [(and (>= (length args) 3) (string=? (cadr args) "--dump"))
     (dump-file (caddr args))]
    ;; Run a file
    [(>= (length args) 2)
     (run-file (cadr args))]
    ;; No arguments — print usage
    [else
     (display "Usage: scheme --script seedink3.scm <file.seed>\n")]))

(main (command-line))

#!/usr/bin/env scheme-script
;; parse-time.scm - Parse Chez Scheme time output and format as JSON/human-readable
;;
;; Usage: scheme --script parse-time.scm [--json] < time-output.txt
;;
;; Parses Chez's time output format and extracts metrics:
;;   - collections (number or "no")
;;   - cpu time (seconds)
;;   - real time (seconds)
;;   - bytes allocated
;;
;; Outputs:
;;   - Human-readable format (default)
;;   - JSON format (--json flag)
;;   - Includes git commit hash

(import (chezscheme))

;; =========================================================================
;; Git utilities
;; =========================================================================

(define (get-git-commit)
  "Get current git commit hash"
  (let-values ([(to-stdin from-stdout from-stderr process-id)
                (open-process-ports "git rev-parse HEAD"
                                    (buffer-mode line)
                                    (native-transcoder))])
    (let ([commit (get-line from-stdout)])
      (close-port to-stdin)
      (close-port from-stdout)
      (close-port from-stderr)
      (if (eof-object? commit)
          "unknown"
          (string-trim commit)))))

(define (string-trim s)
  "Trim whitespace from string"
  (let ([len (string-length s)])
    (if (= len 0)
        s
        (let loop ([start 0] [end len])
          (cond
            [(and (< start end) (char-whitespace? (string-ref s start)))
             (loop (+ start 1) end)]
            [(and (< start end) (char-whitespace? (string-ref s (- end 1))))
             (loop start (- end 1))]
            [else (substring s start end)])))))

;; =========================================================================
;; String utilities
;; =========================================================================

(define (string-contains? str substr)
  "Check if string contains substring"
  (and (string? str)
       (string? substr)
       (let ([slen (string-length str)]
             [sslen (string-length substr)])
         (let loop ([i 0])
           (cond
             [(> (+ i sslen) slen) #f]
             [(string=? (substring str i (+ i sslen)) substr) #t]
             [else (loop (+ i 1))])))))

(define (string-split s delim)
  "Split string by delimiter character"
  (let ([len (string-length s)])
    (let loop ([start 0] [i 0] [parts '()])
      (cond
        [(= i len)
         (reverse (cons (substring s start i) parts))]
        [(char=? (string-ref s i) delim)
         (loop (+ i 1) (+ i 1) (cons (substring s start i) parts))]
        [else
         (loop start (+ i 1) parts)]))))

(define (extract-number-from-line line keyword)
  "Extract a number before a keyword in a line"
  ;; For lines like "    0.000006100s elapsed cpu time"
  ;; or "    50000 bytes allocated"
  (let* ([trimmed (string-trim line)]
         [parts (string-split trimmed #\space)]
         [numbers (filter (lambda (p)
                           (and (> (string-length p) 0)
                                (or (char-numeric? (string-ref p 0))
                                    (and (> (string-length p) 1)
                                         (char=? (string-ref p 0) #\-)
                                         (char-numeric? (string-ref p 1))))))
                         parts)])
    (if (null? numbers)
        #f
        (let ([num-str (car numbers)])
          ;; Remove trailing 's' if present (for time values like "0.123s")
          (let ([cleaned (if (and (> (string-length num-str) 0)
                                  (char=? (string-ref num-str (- (string-length num-str) 1)) #\s))
                             (substring num-str 0 (- (string-length num-str) 1))
                             num-str)])
            (string->number cleaned))))))

;; =========================================================================
;; Time output parsing
;; =========================================================================

(define (parse-time-line line)
  "Parse a single line from Chez time output"
  (cond
    ;; Collections line: "    N collections" or "    no collections"
    [(string-contains? line "no collections")
     '(collections . 0)]

    [(string-contains? line "collections")
     (let ([num (extract-number-from-line line "collections")])
       (if num
           (cons 'collections num)
           #f))]

    ;; CPU time: "    X.XXXXXXXXs elapsed cpu time"
    [(string-contains? line "elapsed cpu time")
     (let ([num (extract-number-from-line line "elapsed")])
       (if num
           (cons 'cpu-time num)
           #f))]

    ;; Real time: "    X.XXXXXXXXs elapsed real time"
    [(string-contains? line "elapsed real time")
     (let ([num (extract-number-from-line line "elapsed")])
       (if num
           (cons 'real-time num)
           #f))]

    ;; Bytes allocated: "    N bytes allocated"
    [(string-contains? line "bytes allocated")
     (let ([num (extract-number-from-line line "bytes")])
       (if num
           (cons 'bytes-allocated num)
           #f))]

    [else #f]))

(define (parse-time-output lines)
  "Parse all lines from Chez time output and return alist of metrics"
  (let loop ([lines lines] [metrics '()])
    (if (null? lines)
        metrics
        (let ([parsed (parse-time-line (car lines))])
          (if parsed
              (loop (cdr lines) (cons parsed metrics))
              (loop (cdr lines) metrics))))))

;; =========================================================================
;; Output formatting
;; =========================================================================

(define (format-human metrics commit)
  "Format metrics as human-readable output"
  (let ([collections (cdr (or (assq 'collections metrics) '(collections . 0)))]
        [cpu-time (cdr (or (assq 'cpu-time metrics) '(cpu-time . 0.0)))]
        [real-time (cdr (or (assq 'real-time metrics) '(real-time . 0.0)))]
        [bytes (cdr (or (assq 'bytes-allocated metrics) '(bytes-allocated . 0)))])
    (printf "Git Commit:      ~a~%" commit)
    (printf "Collections:     ~a~%" collections)
    (printf "CPU Time:        ~as (~ams)~%" cpu-time (* cpu-time 1000))
    (printf "Real Time:       ~as (~ams)~%" real-time (* real-time 1000))
    (printf "Bytes Allocated: ~a (~a MB)~%" bytes (/ bytes 1048576.0))))

(define (format-json metrics commit)
  "Format metrics as JSON"
  (let ([collections (cdr (or (assq 'collections metrics) '(collections . 0)))]
        [cpu-time (cdr (or (assq 'cpu-time metrics) '(cpu-time . 0.0)))]
        [real-time (cdr (or (assq 'real-time metrics) '(real-time . 0.0)))]
        [bytes (cdr (or (assq 'bytes-allocated metrics) '(bytes-allocated . 0)))])
    (printf "{~%")
    (printf "  \"commit\": \"~a\",~%" commit)
    (printf "  \"collections\": ~a,~%" collections)
    (printf "  \"cpu_time_seconds\": ~a,~%" cpu-time)
    (printf "  \"real_time_seconds\": ~a,~%" real-time)
    (printf "  \"bytes_allocated\": ~a,~%" bytes)
    (printf "  \"cpu_time_ms\": ~a,~%" (* cpu-time 1000))
    (printf "  \"real_time_ms\": ~a,~%" (* real-time 1000))
    (printf "  \"memory_mb\": ~a~%" (/ bytes 1048576.0))
    (printf "}~%")))

;; =========================================================================
;; Main
;; =========================================================================

(define (read-all-lines)
  "Read all lines from stdin"
  (let loop ([lines '()])
    (let ([line (get-line (current-input-port))])
      (if (eof-object? line)
          (reverse lines)
          (loop (cons line lines))))))

(define (main args)
  (let* ([json-mode (and (not (null? args)) (string=? (car args) "--json"))]
         [commit (get-git-commit)]
         [lines (read-all-lines)]
         [metrics (parse-time-output lines)])

    (if json-mode
        (format-json metrics commit)
        (format-human metrics commit))))

;; Run main
(main (command-line-arguments))

(letrec ([aif (cons
                'operative
                (lambda (env var test-expr then-expr else-expr)
                  (let ([env env] [%news '()])
                    (let ([%result (let ([val (seed-eval test-expr env)])
                                     (if val
                                         (begin
                                           (let ([v val])
                                             (set! env
                                               (cons (cons var v) env))
                                             (set! %news
                                               (cons (cons var v) %news))
                                             v)
                                           (seed-eval then-expr env))
                                         (seed-eval else-expr env)))])
                      (values (reverse %news) %result)))))])
  (let ([env (list* (cons 'aif aif) env)])
    (begin
      (display '"--- aif examples ---")
      (begin
        (newline)
        (begin
          (let ([val (memv 3 '(1 2 3 4 5))])
            (if val
                (begin
                  (let ([target env] [name 'it] [v val])
                    (set-cdr! target (cons (car target) (cdr target)))
                    (set-car! target (cons name v))
                    v)
                  (let ([it val])
                    (begin (display '"found: ") (display it) (newline))))
                (display '"not found\n")))
          (begin
            (let ([val (let ([proc (env-ref 'assq env)])
                         (if (and (pair? proc) (eq? (car proc) 'operative))
                             ((cdr proc)
                               env
                               ''b
                               ''((a . 1) (b . 2) (c . 3)))
                             (proc 'b '((a . 1) (b . 2) (c . 3)))))])
              (if val
                  (begin
                    (let ([target env] [name 'it] [v val])
                      (set-cdr! target (cons (car target) (cdr target)))
                      (set-car! target (cons name v))
                      v)
                    (let ([it val])
                      (begin
                        (display '"value: ")
                        (display (cdr it))
                        (newline))))
                  (display '"no entry\n")))
            (begin
              (display '"false branch\n")
              (begin
                (let ([val (let ([proc (env-ref 'assq env)])
                             (if (and (pair? proc)
                                      (eq? (car proc) 'operative))
                                 ((cdr proc) env ''x ''((x . 42)))
                                 (proc 'x '((x . 42)))))])
                  (if val
                      (begin
                        (let ([target env] [name 'it] [v val])
                          (set-cdr!
                            target
                            (cons (car target) (cdr target)))
                          (set-car! target (cons name v))
                          v)
                        (let ([it val])
                          (begin
                            (display '"outer it: ")
                            (display (cdr it))
                            (newline)
                            (let ([val (let ([proc (env-ref 'assq env)])
                                         (if (and (pair? proc)
                                                  (eq? (car proc)
                                                       'operative))
                                             ((cdr proc)
                                               env
                                               ''y
                                               ''((y . 99)))
                                             (proc 'y '((y . 99)))))])
                              (if val
                                  (begin
                                    (let ([target env] [name 'it] [v val])
                                      (set-cdr!
                                        target
                                        (cons (car target) (cdr target)))
                                      (set-car! target (cons name v))
                                      v)
                                    (let ([it val])
                                      (begin
                                        (display '"inner it: ")
                                        (display (cdr it))
                                        (newline))))
                                  (display '"not found\n"))))))
                      (display '"not found\n")))
                (begin
                  (let ([target env] [name 'result] [v '42])
                    (set-cdr! target (cons (car target) (cdr target)))
                    (set-car! target (cons name v))
                    v)
                  (let ([result '42])
                    (begin
                      (display '"result: ")
                      (display result)
                      (newline))))))))))))

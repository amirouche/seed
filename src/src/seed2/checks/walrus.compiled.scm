(letrec ([while:= (cons
                    'operative
                    (lambda (env var sep expr . body)
                      (let ([env env] [%news '()])
                        (let ([%result (if (not (eq? sep ':=))
                                           (error 'while:=
                                             '"expected :="
                                             sep)
                                           (letrec ([loop (lambda ()
                                                            (let ([env (list*
                                                                         env)])
                                                              (let ([val (seed-eval
                                                                           expr
                                                                           env)])
                                                                (let ([proc (env-ref
                                                                              'when
                                                                              env)])
                                                                  (if (and (pair?
                                                                             proc)
                                                                           (eq? (car proc)
                                                                                'operative))
                                                                      (let ([env (list*
                                                                                   (cons
                                                                                     'val
                                                                                     val)
                                                                                   (cons
                                                                                     'env
                                                                                     env)
                                                                                   (cons
                                                                                     'var
                                                                                     var)
                                                                                   (cons
                                                                                     'body
                                                                                     body)
                                                                                   (cons
                                                                                     'loop
                                                                                     loop)
                                                                                   env)])
                                                                        ((cdr proc)
                                                                          env
                                                                          'val
                                                                          '(define env
                                                                             var
                                                                             val)
                                                                          '(for-each
                                                                             (lambda (e)
                                                                               (eval
                                                                                 e
                                                                                 env))
                                                                             body)
                                                                          '(loop)))
                                                                      (proc
                                                                        val
                                                                        (let ([v val])
                                                                          (set! env
                                                                            (cons
                                                                              (cons
                                                                                var
                                                                                v)
                                                                              env))
                                                                          (set! %news
                                                                            (cons
                                                                              (cons
                                                                                var
                                                                                v)
                                                                              %news))
                                                                          v)
                                                                        (for-each
                                                                          (lambda (e)
                                                                            (let ([env (list*
                                                                                         (cons
                                                                                           'e
                                                                                           e)
                                                                                         env)])
                                                                              (seed-eval
                                                                                e
                                                                                env)))
                                                                          body)
                                                                        (loop)))))))])
                                             (loop)))])
                          (values (reverse %news) %result)))))]
         [make-file (lambda (chunks) (list chunks))]
         [file-read (lambda (f)
                      (let ([chunks (car f)])
                        (if (null? chunks)
                            #f
                            (let ([chunk (car chunks)])
                              (begin
                                (let ([proc set-car!])
                                  (if (and (pair? proc)
                                           (eq? (car proc) 'operative))
                                      (let ([env (list*
                                                   (cons 'f f)
                                                   (cons 'chunks chunks)
                                                   env)])
                                        ((cdr proc) env 'f '(cdr chunks)))
                                      (proc f (cdr chunks))))
                                chunk)))))])
  (let ([env (list*
               (cons 'while:= while:=)
               (cons 'make-file make-file)
               (cons 'file-read file-read)
               env)])
    (begin
      (display '"--- walrus operator (:=) examples ---")
      (begin
        (newline)
        (begin
          (display '"chunks: ")
          (begin
            (let ([f (make-file '("hello" " " "world" "!"))])
              (let ([proc while:=])
                (if (and (pair? proc) (eq? (car proc) 'operative))
                    (let ([env (list*
                                 (cons 'file-read file-read)
                                 (cons 'f f)
                                 env)])
                      ((cdr proc) env 'chunk ':= '(file-read f)
                        '(display chunk)))
                    (proc
                      (env-ref 'chunk env)
                      (env-ref ':= env)
                      (file-read f)
                      (display (env-ref 'chunk env))))))
            (begin
              (newline)
              (begin
                (display '"sum: ")
                (begin
                  (let ([f (make-file '(10 20 30 40))])
                    (let ([total 0])
                      (begin
                        (letrec ([loop (lambda ()
                                         (let ([env (list* env)])
                                           (let ([val (file-read f)])
                                             (let ([proc (env-ref
                                                           'when
                                                           env)])
                                               (if (and (pair? proc)
                                                        (eq? (car proc)
                                                             'operative))
                                                   (let ([env (list*
                                                                (cons
                                                                  'val
                                                                  val)
                                                                (cons
                                                                  'env
                                                                  env)
                                                                (cons
                                                                  'loop
                                                                  loop)
                                                                env)])
                                                     ((cdr proc) env 'val
                                                       '(define env 'n val)
                                                       '(for-each
                                                          (lambda (e)
                                                            (eval e env))
                                                          '((set! total
                                                              (+ total
                                                                 n))))
                                                       '(loop)))
                                                   (proc
                                                     val
                                                     (let ([target env]
                                                           [name 'n]
                                                           [v val])
                                                       (set-cdr!
                                                         target
                                                         (cons
                                                           (car target)
                                                           (cdr target)))
                                                       (set-car!
                                                         target
                                                         (cons name v))
                                                       v)
                                                     (for-each
                                                       (lambda (e)
                                                         (let ([env (list*
                                                                      (cons
                                                                        'e
                                                                        e)
                                                                      env)])
                                                           (seed-eval
                                                             e
                                                             env)))
                                                       '((set! total
                                                           (+ total n))))
                                                     (loop)))))))])
                          (loop))
                        (display total))))
                  (begin
                    (newline)
                    (begin
                      (display '"found: ")
                      (begin
                        (let ([f (make-file '(1 3 5 8 11 13))])
                          (let ([found #f])
                            (begin
                              (letrec ([loop (lambda ()
                                               (let ([env (list* env)])
                                                 (let ([val (file-read f)])
                                                   (let ([proc (env-ref
                                                                 'when
                                                                 env)])
                                                     (if (and (pair? proc)
                                                              (eq? (car proc)
                                                                   'operative))
                                                         (let ([env (list*
                                                                      (cons
                                                                        'val
                                                                        val)
                                                                      (cons
                                                                        'env
                                                                        env)
                                                                      (cons
                                                                        'loop
                                                                        loop)
                                                                      env)])
                                                           ((cdr proc) env 'val
                                                             '(define env
                                                                'x
                                                                val)
                                                             '(for-each
                                                                (lambda (e)
                                                                  (eval
                                                                    e
                                                                    env))
                                                                '((when (even?
                                                                          x)
                                                                    (unless found
                                                                      (set! found
                                                                        x)))))
                                                             '(loop)))
                                                         (proc
                                                           val
                                                           (let ([target env]
                                                                 [name 'x]
                                                                 [v val])
                                                             (set-cdr!
                                                               target
                                                               (cons
                                                                 (car target)
                                                                 (cdr target)))
                                                             (set-car!
                                                               target
                                                               (cons
                                                                 name
                                                                 v))
                                                             v)
                                                           (for-each
                                                             (lambda (e)
                                                               (let ([env (list*
                                                                            (cons
                                                                              'e
                                                                              e)
                                                                            env)])
                                                                 (seed-eval
                                                                   e
                                                                   env)))
                                                             '((when (even?
                                                                       x)
                                                                 (unless found
                                                                   (set! found
                                                                     x)))))
                                                           (loop)))))))])
                                (loop))
                              (display found))))
                        (begin
                          (newline)
                          (begin
                            (display '"matrix: ")
                            (begin
                              (let ([rows (make-file
                                            (list
                                              (make-file '(1 2 3))
                                              (make-file '(4 5 6))
                                              (make-file '(7 8 9))))])
                                (let ([proc while:=])
                                  (if (and (pair? proc)
                                           (eq? (car proc) 'operative))
                                      (let ([env (list*
                                                   (cons
                                                     'file-read
                                                     file-read)
                                                   (cons 'rows rows)
                                                   (cons 'while:= while:=)
                                                   env)])
                                        ((cdr proc) env 'row ':= '(file-read rows)
                                          '(while:= cell := (file-read row)
                                             (display cell)
                                             (display " "))))
                                      (proc
                                        (env-ref 'row env)
                                        (env-ref ':= env)
                                        (file-read rows)
                                        (let ([proc while:=])
                                          (if (and (pair? proc)
                                                   (eq? (car proc)
                                                        'operative))
                                              (let ([env (list*
                                                           (cons
                                                             'file-read
                                                             file-read)
                                                           env)])
                                                ((cdr proc) env 'cell ':=
                                                  '(file-read row)
                                                  '(display cell)
                                                  '(display " ")))
                                              (proc (env-ref 'cell env)
                                                (env-ref ':= env)
                                                (file-read
                                                  (env-ref 'row env))
                                                (display
                                                  (env-ref 'cell env))
                                                (display '" "))))))))
                              (newline))))))))))))))))

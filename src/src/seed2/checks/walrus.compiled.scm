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
                                                                (if val
                                                                    (begin
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
                                                                      (loop))
                                                                    (void)))))])
                                             (loop)))])
                          (values (reverse %news) %result)))))]
         [make-file (lambda (chunks) (list chunks))]
         [file-read (lambda (f)
                      (let ([chunks (car f)])
                        (if (null? chunks)
                            #f
                            (let ([chunk (car chunks)])
                              (begin (set-car! f (cdr chunks)) chunk)))))])
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
              (letrec ([loop (lambda ()
                               (let ([env (list* env)])
                                 (let ([val (file-read f)])
                                   (if val
                                       (begin
                                         (let ([target env]
                                               [name 'chunk]
                                               [v val])
                                           (set-cdr!
                                             target
                                             (cons
                                               (car target)
                                               (cdr target)))
                                           (set-car! target (cons name v))
                                           v)
                                         (let ([chunk val])
                                           (begin
                                             (for-each
                                               (lambda (e)
                                                 (let ([env (list*
                                                              (cons 'e e)
                                                              env)])
                                                   (seed-eval e env)))
                                               '((display chunk)))
                                             (loop))))
                                       (void)))))])
                (loop)))
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
                    (letrec ([loop (lambda ()
                                     (let ([env (list* env)])
                                       (let ([val (file-read rows)])
                                         (if val
                                             (begin
                                               (let ([target env]
                                                     [name 'row]
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
                                               (let ([row val])
                                                 (begin
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
                                                     '((while:= cell :=
                                                         (file-read row)
                                                         (display cell)
                                                         (display " "))))
                                                   (loop))))
                                             (void)))))])
                      (loop)))
                  (newline))))))))))

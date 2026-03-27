(letrec ([setup (cons
                  'operative
                  (lambda (env)
                    (let ([env env] [%news '()])
                      (let ([%result (begin
                                       (let ([v 42])
                                         (set! env
                                           (cons
                                             (cons (env-ref 'x env) v)
                                             env))
                                         (set! %news
                                           (cons
                                             (cons (env-ref 'x env) v)
                                             %news))
                                         v)
                                       (let ([v 99])
                                         (set! env
                                           (cons
                                             (cons (env-ref 'y env) v)
                                             env))
                                         (set! %news
                                           (cons
                                             (cons (env-ref 'y env) v)
                                             %news))
                                         v))])
                        (values (reverse %news) %result)))))])
  (let ([env (list* (cons 'setup setup) env)])
    (call-with-values
      (lambda () (values (list 42 99) (list #f)))
      (lambda (news out)
        (call-with-values
          (lambda () (apply values news))
          (lambda (x y)
            (call-with-values
              (lambda () (apply values out))
              (lambda (#{ret hl3loetar5mvqefltmmiofigp-586})
                (begin
                  (display x)
                  (begin
                    (display '" ")
                    (begin (display y) (newline))))))))))))

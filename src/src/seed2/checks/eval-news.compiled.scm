(letrec ([my-def (cons
                   'operative
                   (lambda (env name val-expr)
                     (let ([env env] [%news '()])
                       (let ([%result (let ([v (seed-eval val-expr env)])
                                        (set! env (cons (cons name v) env))
                                        (set! %news
                                          (cons (cons name v) %news))
                                        v)])
                         (values (reverse %news) %result)))))]
         [test-eval (cons
                      'operative
                      (lambda (env)
                        (let ([env env])
                          (seed-eval
                            '(begin
                               (my-def x 42)
                               (my-def y (+ x 1))
                               (+ x y))
                            env))))])
  (let ([env (list*
               (cons 'my-def my-def)
               (cons 'test-eval test-eval)
               env)])
    (begin
      (display
        (seed-eval
          '(begin (my-def x 42) (my-def y (+ x 1)) (+ x y))
          env))
      (newline))))

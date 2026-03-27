(letrec ([my-op (cons
                  'operative
                  (lambda (env x)
                    (let ([env env] [%news '()])
                      (let ([%result (begin
                                       (let ([v (+ 40 2)])
                                         (set! env (cons (cons x v) env))
                                         (set! %news
                                           (cons (cons x v) %news))
                                         v)
                                       (+ 40 1))])
                        (values (reverse %news) %result)))))])
  (let ([env (list* (cons 'my-op my-op) env)])
    (call-with-values
      (lambda () (values (list 42) (list 41)))
      (lambda (news out)
        (call-with-values
          (lambda () (apply values news))
          (lambda (dummy)
            (call-with-values
              (lambda () (apply values out))
              (lambda (#{ret gmpy8dk2zagg4pqk2cwql1z7b-586})
                (begin (display dummy) (newline))))))))))

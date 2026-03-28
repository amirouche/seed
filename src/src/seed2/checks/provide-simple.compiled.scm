(letrec ([my-def (cons
                   'operative
                   (lambda (env name val)
                     (let ([e env] [%news '()])
                       (let ([%result (let ([v (seed-eval val e)])
                                        (set! env (cons (cons name v) env))
                                        (set! %news
                                          (cons (cons name v) %news))
                                        v)])
                         (values (reverse %news) %result)))))])
  (let ([env (list* (cons 'my-def my-def) env)])
    (call-with-values
      (lambda () (values (list 42) (list #f)))
      (lambda (news out)
        (call-with-values
          (lambda () (apply values news))
          (lambda (x)
            (call-with-values
              (lambda () (values (list (+ x 1)) (list #f)))
              (lambda (news out)
                (call-with-values
                  (lambda () (apply values news))
                  (lambda (y)
                    (begin
                      (display x)
                      (begin
                        (display '" ")
                        (begin (display y) (newline))))))))))))))

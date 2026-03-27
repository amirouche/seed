(letrec ([frob (cons
                 'operative
                 (lambda (env a a*)
                   (let ([env env] [%news '()])
                     (let ([%result (begin
                                      (let ([v (+ 40 2 (seed-eval a env))])
                                        (set! env (cons (cons a* v) env))
                                        (set! %news
                                          (cons (cons a* v) %news))
                                        v)
                                      (+ 40 1 (seed-eval a env)))])
                       (values (reverse %news) %result)))))])
  (let ([env (list* (cons 'frob frob) env)])
    (call-with-values
      (lambda () (values (list 43) (list 42)))
      (lambda (news out)
        (call-with-values
          (lambda () (apply values news))
          (lambda (next)
            (call-with-values
              (lambda () (apply values out))
              (lambda (#{vau-result c5qm3wwe9itpqg9uogvfkin10-586})
                (begin
                  (display #{vau-result c5qm3wwe9itpqg9uogvfkin10-586})
                  (begin
                    (newline)
                    (begin (display next) (newline))))))))))))

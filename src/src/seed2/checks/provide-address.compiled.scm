(letrec ([provide (cons
                    'operative
                    (lambda (env symbols . body)
                      (let ([env env])
                        (seed-eval
                          (list
                            (env-ref 'define env)
                            symbols
                            (list
                              (env-ref 'let env)
                              '()
                              (list* (env-ref 'begin env) body)
                              (list* list symbols)))
                          env))))])
  (let ([env (list* (cons 'provide provide) env)])
    (begin
      (seed-eval
        (list
          (env-ref 'define env)
          '(address
             address?
             address-street
             address-city
             address-country)
          (list
            (env-ref 'let env)
            '()
            (list*
              (env-ref 'begin env)
              '((define (addr-ctor address? addr-dtor)
                  (make-encapsulation-type))
                 (define address
                   (lambda (street city country)
                     (addr-ctor (list street city country))))
                 (define address-street
                   (lambda (addr) (car (addr-dtor addr))))
                 (define address-city
                   (lambda (addr) (cadr (addr-dtor addr))))
                 (define address-country
                   (lambda (addr) (caddr (addr-dtor addr))))))
            (list*
              list
              '(address
                 address?
                 address-street
                 address-city
                 address-country))))
        env)
      (letrec ([home (let ([proc (env-ref 'address env)])
                       (if (and (pair? proc) (eq? (car proc) 'operative))
                           ((cdr proc)
                             env
                             '"Rue de la Paix"
                             '"Grand Paris"
                             '"France")
                           (proc
                             '"Rue de la Paix"
                             '"Grand Paris"
                             '"France")))])
        (begin
          (display
            (let ([proc (env-ref 'address-street env)])
              (if (and (pair? proc) (eq? (car proc) 'operative))
                  ((cdr proc) env 'home)
                  (proc home))))
          (begin
            (display '" in city of ")
            (begin
              (display
                (let ([proc (env-ref 'address-city env)])
                  (if (and (pair? proc) (eq? (car proc) 'operative))
                      ((cdr proc) env 'home)
                      (proc home))))
              (begin
                (display '" in country dubbed ")
                (begin
                  (display
                    (let ([proc (env-ref 'address-country env)])
                      (if (and (pair? proc) (eq? (car proc) 'operative))
                          ((cdr proc) env 'home)
                          (proc home))))
                  (newline))))))))))

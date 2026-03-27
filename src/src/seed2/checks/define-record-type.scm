(letrec ([define-record-type (cons
                               'operative
                               (lambda (env type-name ctor-spec pred-name .
                                        field-specs)
                                 (let ([env env] [%news '()])
                                   (let ([%result (let ([ctor-name (car ctor-spec)]
                                                        [ctor-fields (cdr ctor-spec)])
                                                    (let ([#{vals dyzkgdfqns3fkq2g5fi2o8n0n-586} ((env-ref
                                                                                                    'make-encapsulation-type
                                                                                                    env))])
                                                      (let ([wrap (list-ref
                                                                    #{vals dyzkgdfqns3fkq2g5fi2o8n0n-586}
                                                                    0)]
                                                            [pred? (list-ref
                                                                     #{vals dyzkgdfqns3fkq2g5fi2o8n0n-586}
                                                                     1)]
                                                            [unwrap (list-ref
                                                                      #{vals dyzkgdfqns3fkq2g5fi2o8n0n-586}
                                                                      2)])
                                                        (begin
                                                          (let ([v (lambda fields
                                                                     (wrap
                                                                       fields))])
                                                            (set! env
                                                              (cons
                                                                (cons
                                                                  ctor-name
                                                                  v)
                                                                env))
                                                            (set! %news
                                                              (cons
                                                                (cons
                                                                  ctor-name
                                                                  v)
                                                                %news))
                                                            v)
                                                          (begin
                                                            (let ([v pred?])
                                                              (set! env
                                                                (cons
                                                                  (cons
                                                                    pred-name
                                                                    v)
                                                                  env))
                                                              (set! %news
                                                                (cons
                                                                  (cons
                                                                    pred-name
                                                                    v)
                                                                  %news))
                                                              v)
                                                            (let loop ([specs field-specs])
                                                              (if (null?
                                                                    specs)
                                                                  #f
                                                                  (let ([field-spec (car specs)])
                                                                    (let ([field-name (car field-spec)]
                                                                          [accessor-name (cadr
                                                                                           field-spec)])
                                                                      (begin
                                                                        (let ([v (let ([idx (let index-of ([sym field-name]
                                                                                                           [lst ctor-fields]
                                                                                                           [i 0])
                                                                                              (if (null?
                                                                                                    lst)
                                                                                                  0
                                                                                                  (if (eq? sym
                                                                                                           (car lst))
                                                                                                      i
                                                                                                      (index-of
                                                                                                        sym
                                                                                                        (cdr lst)
                                                                                                        (+ i
                                                                                                           1)))))])
                                                                                   (lambda (r)
                                                                                     (list-ref
                                                                                       (unwrap
                                                                                         r)
                                                                                       idx)))])
                                                                          (set! env
                                                                            (cons
                                                                              (cons
                                                                                accessor-name
                                                                                v)
                                                                              env))
                                                                          (set! %news
                                                                            (cons
                                                                              (cons
                                                                                accessor-name
                                                                                v)
                                                                              %news))
                                                                          v)
                                                                        (loop
                                                                          (cdr specs))))))))))))])
                                     (values (reverse %news) %result)))))])
  (let ([env (list*
               (cons 'define-record-type define-record-type)
               env)])
    (call-with-values
      (lambda ()
        (let ([#{vals dyzkgdfqns3fkq2g5fi2o8n0n-586} ((env-ref
                                                        'make-encapsulation-type
                                                        env))])
          (let ([wrap (list-ref
                        #{vals dyzkgdfqns3fkq2g5fi2o8n0n-586}
                        0)]
                [pred? (list-ref #{vals dyzkgdfqns3fkq2g5fi2o8n0n-586} 1)]
                [unwrap (list-ref
                          #{vals dyzkgdfqns3fkq2g5fi2o8n0n-586}
                          2)])
            (values
              (list
                (lambda fields (wrap fields))
                pred?
                (let ([idx (letrec ([index-of (lambda (sym lst i)
                                                (if (null? lst)
                                                    0
                                                    (if (eq? sym (car lst))
                                                        i
                                                        (index-of
                                                          sym
                                                          (cdr lst)
                                                          (+ i 1)))))])
                             '0)])
                  (lambda (r) (list-ref (unwrap r) idx)))
                (let ([idx (letrec ([index-of (lambda (sym lst i)
                                                (if (null? lst)
                                                    0
                                                    (if (eq? sym (car lst))
                                                        i
                                                        (index-of
                                                          sym
                                                          (cdr lst)
                                                          (+ i 1)))))])
                             '1)])
                  (lambda (r) (list-ref (unwrap r) idx))))
              (list #f)))))
      (lambda (news out)
        (call-with-values
          (lambda () (apply values news))
          (lambda (kons kons? kons-head kons-tail)
            (call-with-values
              (lambda () (apply values out))
              (lambda (#{ret dyzkgdfqns3fkq2g5fi2o8n0n-587})
                (letrec ([my-immutable-pair (kons 4 3)])
                  (begin
                    (display (kons-head my-immutable-pair))
                    (begin
                      (display (kons-tail my-immutable-pair))
                      (newline))))))))))))

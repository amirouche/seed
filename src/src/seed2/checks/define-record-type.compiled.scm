(letrec ([define-record-type (cons
                               'operative
                               (lambda (env type-name ctor-spec pred-name .
                                        field-specs)
                                 (let ([env env] [%news '()])
                                   (let ([%result (let ([ctor-name (car ctor-spec)]
                                                        [ctor-fields (cdr ctor-spec)])
                                                    (let ([#{vals brnxapkpgfo3fdbjobzbvejar-628} (let ([proc (env-ref
                                                                                                               'make-encapsulation-type
                                                                                                               env)])
                                                                                                   (if (and (pair?
                                                                                                              proc)
                                                                                                            (eq? (car proc)
                                                                                                                 'operative))
                                                                                                       ((cdr proc)
                                                                                                         env)
                                                                                                       (proc)))])
                                                      (let ([wrap (list-ref
                                                                    #{vals brnxapkpgfo3fdbjobzbvejar-628}
                                                                    0)]
                                                            [pred? (list-ref
                                                                     #{vals brnxapkpgfo3fdbjobzbvejar-628}
                                                                     1)]
                                                            [unwrap (list-ref
                                                                      #{vals brnxapkpgfo3fdbjobzbvejar-628}
                                                                      2)])
                                                        (begin
                                                          (let ([v (lambda fields
                                                                     (let ([proc wrap])
                                                                       (if (and (pair?
                                                                                  proc)
                                                                                (eq? (car proc)
                                                                                     'operative))
                                                                           ((cdr proc)
                                                                             env
                                                                             'fields)
                                                                           (proc
                                                                             fields))))])
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
                                                                                       (let ([proc unwrap])
                                                                                         (if (and (pair?
                                                                                                    proc)
                                                                                                  (eq? (car proc)
                                                                                                       'operative))
                                                                                             ((cdr proc)
                                                                                               env
                                                                                               'r)
                                                                                             (proc
                                                                                               r)))
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
        (let ([#{vals brnxapkpgfo3fdbjobzbvejar-628} (let ([proc (env-ref
                                                                   'make-encapsulation-type
                                                                   env)])
                                                       (if (and (pair?
                                                                  proc)
                                                                (eq? (car proc)
                                                                     'operative))
                                                           ((cdr proc) env)
                                                           (proc)))])
          (let ([wrap (list-ref
                        #{vals brnxapkpgfo3fdbjobzbvejar-628}
                        0)]
                [pred? (list-ref #{vals brnxapkpgfo3fdbjobzbvejar-628} 1)]
                [unwrap (list-ref
                          #{vals brnxapkpgfo3fdbjobzbvejar-628}
                          2)])
            (values
              (list
                (lambda fields
                  (let ([proc wrap])
                    (if (and (pair? proc) (eq? (car proc) 'operative))
                        ((cdr proc) env 'fields)
                        (proc fields))))
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
                  (lambda (r)
                    (list-ref
                      (let ([proc unwrap])
                        (if (and (pair? proc) (eq? (car proc) 'operative))
                            ((cdr proc) env 'r)
                            (proc r)))
                      idx)))
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
                  (lambda (r)
                    (list-ref
                      (let ([proc unwrap])
                        (if (and (pair? proc) (eq? (car proc) 'operative))
                            ((cdr proc) env 'r)
                            (proc r)))
                      idx))))
              (list #f)))))
      (lambda (news out)
        (call-with-values
          (lambda () (apply values news))
          (lambda (kons kons? kons-head kons-tail)
            (letrec ([my-immutable-pair (let ([proc kons])
                                          (if (and (pair? proc)
                                                   (eq? (car proc)
                                                        'operative))
                                              ((cdr proc) env '4 '3)
                                              (proc 4 3)))])
              (begin
                (display
                  (let ([proc kons-head])
                    (if (and (pair? proc) (eq? (car proc) 'operative))
                        ((cdr proc) env 'my-immutable-pair)
                        (proc my-immutable-pair))))
                (begin
                  (display
                    (let ([proc kons-tail])
                      (if (and (pair? proc) (eq? (car proc) 'operative))
                          ((cdr proc) env 'my-immutable-pair)
                          (proc my-immutable-pair))))
                  (newline))))))))))

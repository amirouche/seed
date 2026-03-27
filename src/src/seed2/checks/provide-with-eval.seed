;; Test: provide macro using eval-based runtime fallback path.
;; Same as provide-address but exercises the runtime eval path
;; where provide constructs and evals define expressions dynamically.
(define provide
          (vau (symbols . body) env
                (eval 
                 (list define 
                       symbols 
                       (list let ()
                             (list* begin body)
                             (list* list symbols)))
                 env)))

(provide 
    (address 
     address? 
     address-street
     address-city 
     address-country)

    (define (addr-ctor address? addr-dtor)
        (make-encapsulation-type))
              
    (define address
        (lambda (street city country)
            (addr-ctor (list street city country))))
            
    (define address-street
        (lambda (addr)
            (car (addr-dtor addr))))
            
    (define address-city
        (lambda (addr)
            (cadr (addr-dtor addr))))
            
    (define address-country
        (lambda (addr)
                 (caddr (addr-dtor addr)))))

(define home (address "Rue de la Paix" "Grand Paris" "France"))

(display (address-street home))
(display " in city of ")
(display (address-city home))
(display " in country dubbed ")
(display (address-country home))
(newline)

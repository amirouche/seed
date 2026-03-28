;; Test: define-record-type as a vau macro.
;; Demonstrates a complex operative that exports a constructor, predicate,
;; and field accessors into the caller's environment using define-env.
(define define-record-type
          (vau (type-name ctor-spec pred-name . field-specs) env

                 ;; destructure ctor-spec: (ctor-name field1 field2 ...)
                 (let ((ctor-name (car ctor-spec))
                       (ctor-fields (cdr ctor-spec)))

                   ;; generate a disjoint type, predicate, and unwrapper
                   (define (wrap pred? unwrap) (make-encapsulation-type))

                   ;; export constructor to caller
                   (define env ctor-name
                     (lambda fields (wrap fields)))

                   ;; export predicate to caller
                   (define env pred-name pred?)

                   ;; export accessors — look up each field's position in ctor-fields
                   (let loop ((specs field-specs))
                     (if (null? specs) #f
                         (let ((field-spec (car specs)))
                           (let ((field-name (car field-spec))
                                 (accessor-name (cadr field-spec)))
                             (define env accessor-name
                               (let ((idx (let index-of ((sym field-name) (lst ctor-fields) (i 0))
                                            (if (null? lst) 0
                                                (if (eq? sym (car lst)) i
                                                    (index-of sym (cdr lst) (+ i 1)))))))
                                 (lambda (r) (list-ref (unwrap r) idx))))
                             (loop (cdr specs)))))))))

(define-record-type <kons>
  (kons head tail)
  kons?
  (head kons-head)
  (tail kons-tail))

(define my-immutable-pair (kons 4 3))

(display (kons-head my-immutable-pair))
(display (kons-tail my-immutable-pair))
(newline)

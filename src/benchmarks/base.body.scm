(define dev!
  (lambda (active?)
    (if active?
        (begin
          (optimize-level 0)
          (collect-request-handler (lambda () (collect)))
          (compile-profile 'source))
        (begin
          (optimize-level 2)
          (collect-request-handler void)))
    (import-notify active?)
    (generate-allocation-counts active?)
    (generate-covin-files active?)
    (generate-inspector-information active?)
    (generate-instruction-counts active?)
    (generate-interrupt-trap active?)
    (generate-procedure-source-information active?)
    (generate-profile-forms active?)
    (debug-on-exception active?)))

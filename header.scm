
(define header-asm
  `((jp boot)
    (db ,(map char->integer (string->list "SK")))
    (db (0 0))

    (dec sp)
    (ret)
    ,@(apply append (make-list 5 `(,@ (make-list 7 '(nop))
                                      (ret))))
    ,@(make-list 7 '(nop))
    (jp sys-interrupt)
    ,@(make-list 24 '(nop))
    (jp boot)
    (db (#xff #xa5 #xff))))

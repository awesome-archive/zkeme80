(define (string s)
  `(,@(map char->integer (string->list s)) 0))

;; At assembly time, print the value of the program counter.
(define PRINT-PC
  (lambda ()
    (format #t "~a\n" (num->hex *pc*))
    ;; Macros need to return () or an instruction record..
    '()))

;; Multiple pushes.
(define (push* l)
  (map (lambda (x) `(push ,x))
       l))

;; Multple pops.
(define (pop* l)
  (map (lambda (x) `(pop ,x))
       l))

;; Multiple calls.
(define (call* l)
  (map (lambda (x) `(call ,x))
       l))

;; Relative jumps like JR $+3
;; Write ,(jr-rel 3) instead in the quasi-quoted program.
(define (jr-rel amount)
  (lambda () (assemble-expr `(jr `,(+ *pc* ,amount))))
  )

;; Constant symbols. VAL must be an integer
(define (equ sym val)
  (lambda ()
    (if (not (16-bit-imm? val))
        (error (format #f "Error in equ: Cannot set ~a to ~a." sym val))
        (add-label! sym val))
    '()))

(define-syntax with-regs-preserve
  (syntax-rules ()
    ((_ (reg reg* ...) body body* ...)
     `(,@(push* '(reg reg* ...))
       body body* ...
       ,@(pop* (reverse '(reg reg* ...)))))))


;; Assembling this program should yield a bit-for-bit identical binary
;; to that of the SmileyOS kernel (a minimal OS that draws a smiley to
;; the screen).  I'm using it because it's the "minimum viable" OS, as
;; it includes everything from unlocking flash to unlocking the screen
;; and other stuff I'm not currently interested in.

(define swap-sector #x38)
(define smiley-os
  `(,(equ 'flash-executable-ram #x8000)
    ,(equ 'flash-executable-ram-size 100)
    (jp boot)
    (ld d e)
    (ld c e)
    (nop)
    (nop)
    (dec sp)
    (ret)
    ,@(apply append (make-list 5 `(,@ (make-list 7 '(nop))
                                      (ret))))
    ,@(make-list 7 '(nop))
    (jp sys-interrupt)
    ,@(make-list 24 '(nop))
    (jp boot)
    (db (#xff #xa5 #xff))
    
    (label boot)
    (label shutdown)
    (di)
    (ld a #x6)
    (out (4) a)
    (ld a #x81)
    (out (7) a)
    (ld sp 0)
    (call sleep)
    
    (label restart)
    (label reboot)
    (di)
    (ld sp 0)
    (ld a 6)
    (out (4) a)
    (ld a #x81)
    (out (7) a)
    (ld a 3)
    (out (#xe) a)
    (xor a)
    (out (#xf) a)
    (call unlock-flash)
    (xor a)
    (out (#x25) a)
    (dec a)
    (out (#x26) a)
    (out (#x23) a)
    (out (#x22) a)
    (call lock-flash)
    (ld a 1)
    (out (#x20) a)

    
    (ld a #b0001011)
    (out (3) a)
    (ld hl #x8000)
    (ld (hl) 0)
    (ld de #x8001)
    (ld bc #x7fff)
    (ldir)

    ;; Arbitrarily complicated macros!
    ,@(apply append (map (lambda (x)
                           `((ld a ,x)
                             ;; (call #x50f)
                             (call lcd-delay)
                             (out (#x10) a)))
                         '(5 1 3 #x17 #xb #xef)))

    ;; "main", after everything has been set up.
    (ld iy #x8100)
    (ld hl smiley-face)
    (ld b 4)
    (ld de 0)
    (call put-sprite-or)
    (call fast-copy)
    (call flush-keys)
    (call wait-key)
    (push iy)
    (ld iy 0)
    (call fast-copy)
    (pop iy)
    (call flush-keys)
    (call wait-key)
    (push iy)
    (ld iy #x8100)
    (ld e 10)
    (ld l 10)
    (ld b 10)
    (ld c 10)
    (call rect-or)
    (call fast-copy)
    (call flush-keys)
    (call wait-key)
    (pop iy)

    (jp shutdown)

    (label smiley-face)
    (db (#b01010000))
    (db (#b00000000))
    (db (#b10001000))
    (db (#b01110000))
    
    
    (label sys-interrupt)
    (di)
    ,@(push* '(af bc de hl ix iy))
    (exx)
    ((ex af afs))
    ,@(push* '(af bc de hl))
    (jp usb-interrupt)
    (label interrupt-resume)
    (in a (4))
    (bit 0 a)
    (jr nz int-handle-on)
    (bit 1 a)
    (jr nz int-handle-timer1)
    (bit 2 a)
    (jr nz int-handle-timer2)
    (bit 4 a)
    (jr nz int-handle-link)
    (jr sys-interrupt-done)
    
    (label int-handle-on)
    (in a (3))
    (res 0 a)
    (out (3) a)
    (set 0 a)
    (out (3) a)
    (jr sys-interrupt-done)
    
    (label int-handle-timer1)
    (in a (3))
    (res 1 a)
    (out (3) a)
    (set 1 a)
    (out (3) a)
    (jr sys-interrupt-done)

    (label int-handle-timer2)
    (in a (3))
    (res 2 a)
    (out (3) a)
    (set 2 a)
    (out (3) a)
    (jr sys-interrupt-done)
    
    (label int-handle-link)
    (in a (3))
    (res 4 a)
    (out (3) a)
    (set 4 a)
    (out (3) a)
    
    (label sys-interrupt-done)
    
    ,@(pop* '(hl de bc af))
    (exx)
    ((ex af afs))
    ,@(pop* '(iy ix hl de bc af))
    (ei)
    (ret)
    (label usb-interrupt)
    (in a (#x55))
    (bit 0 a)
    (jr z usb-unknown-event)
    (bit 2 a)
    (jr z usb-line-event)
    (bit 4 a)
    (jr z usb-protocol-event)
    (jp interrupt-resume)
    (label usb-unknown-event)
    (jp interrupt-resume)
    (label usb-line-event)

    (in a (#x56))
    (xor #xff)
    (out (#x57) a)
    (jp interrupt-resume)

    (label usb-protocol-event)
    ,@(map (lambda (x) `(in a (,x)))
           '(#x82 #x83 #x84 #x85 #x86))

    (jp interrupt-resume)
    
    (label write-flash-byte)
    (push bc)
    (ld b a)
    (push af)
    (ld a i)
    (push af)
    (di)
    (ld a b)
    ,@(push* '(hl de bc hl de bc))

    (ld hl write-flash-byte-ram)
    (ld de flash-executable-ram)
    (ld bc #x1f)
    (ldir)
    ,@(pop* '(bc de hl))
    (call flash-executable-ram)
    ,@(pop* '(bc de hl af))
    (jp po local-label1)
    (ei)
    (label local-label1)
    ,@(pop* '(af bc))
    (ret)
    (label write-flash-byte-ram)
    (and (hl))
    (ld b a)
    (ld a #xaa)
    (ld (#xaaa) a)
    (ld a #x55)
    (ld (#x555) a)
    (ld a #xa0)
    (ld (#xaaa) a)
    (ld (hl) b)
    (label local-label2)
    (ld a b)
    (xor (hl))
    (bit 7 a)
    (jr z write-flash-byte-done)
    (bit 5 (hl))
    (jr z local-label2)
    (label write-flash-byte-done)
    (ld (hl) #xf0)
    (ret)
    
    (label write-flash-byte-ram-end)
    
    (label write-flash-buffer)
    (push af)
    (ld a i)
    (push af)
    (di)
    ,@(push* '(hl de bc hl de bc))
    (ld hl write-flash-buffer-ram)
    (ld de flash-executable-ram)
    (ld bc #x2c)
    (ldir)
    ,@(pop* '(bc de hl))
    (call flash-executable-ram)
    ,@(pop* '(bc de hl af))
    (jp po local-label3)
    (ei)
    (label local-label3)
    (pop af)
    (ret)

    (label write-flash-buffer-ram)
    (label write-flash-buffer-loop)
    (ld a #xaa)
    (ld (#xaaa) a)
    (ld a #x55)
    (ld (#x555) a)
    (ld a #xa0)
    (ld (#xaaa) a)
    (ld a (hl))
    (ld (de) a)
    (inc de)
    (dec bc)
    
    (label local-label4)
    (xor (hl))
    (bit 7 a)
    (jr z local-label5)
    (bit 5 a)
    (jr z local-label4)
    (ld a #xf0)
    (ld (0) a)
    (ret)
    (label local-label5)
    (inc hl)
    (ld a b)
    (or a)
    (jr nz write-flash-buffer-loop)
    (ld a c)
    (or a)
    (jr nz write-flash-buffer-loop)
    (ret)
    
    (label write-flash-buffer-ram-end)
    
    (label erase-flash-sector)
    (push bc)
    (ld b a)
    (push af)
    (ld a i)
    (ld a i)
    (push af)
    (di)
    (ld a b)
    ,@(push* '(hl de bc hl de bc))
    (ld hl erase-flash-sector-ram)
    (ld de flash-executable-ram)
    (ld bc #x30)
    (ldir)
    ,@(pop* '(bc de hl))
    (call flash-executable-ram)
    ,@(pop* '(bc de hl af))
    (jp po local-label6)
    (ei)
    (label local-label6)
    (pop af)
    (pop bc)
    (ret)
    
    (label erase-flash-sector-ram)
    (out (6) a)
    (ld a #xaa)
    (ld (#x0aaa) a)
    (ld a #x55)
    (ld (#x0555) a)
    (ld a #x80)
    (ld (#x0aaa) a)
    (ld a #xaa)
    (ld (#x0aaa) a)
    (ld a #x55)
    (ld (#x0555) a)
    (ld a #x30)
    (ld (#x4000) a)
    (label local-label7)
    (ld a (#x4000))
    (bit 7 a)
    (ret nz)
    (bit 5 a)
    (jr z local-label7)
    (ld a #xf0)
    (ld (#x4000) a)
    (ret)
    (label erase-flash-sector-ram-end)

    (label erase-flash-page)
    ,@(push* '(af bc af))
    (call copy-sector-to-swap)
    (pop af)
    (push af)
    (call erase-flash-sector)
    (pop af)
    (ld c a)
    (and #b11111100)
    (ld b ,swap-sector)
    (label local-label8)
    (cp c)
    (jr z local-label9)
    (call #x32d)
    (label local-label9)
    (inc b)
    (inc a)
    (push af)
    (ld a b)
    (and #b11111100)
    (or a)
    (jr z local-label10)
    (pop af)
    (jr local-label8)
    (label local-label10)
    ,@(pop* '(af bc af))
    (ret)
    
    (label erase-flash-page-ram)
    (label copy-sector-to-swap)
    (push af)
    ;; (db (#xff #xff #xff))
    (ld a ,swap-sector)
    (call erase-flash-sector)
    (pop af)
    (push bc)
    (ld b a)
    (push af)
    (ld a i)
    (ld a i)
    (push af)
    (di)
    (ld a b)
    (and #b11111100)
    (push hl)
    (push de)
    ;; (ld hl copy-sector-to-swap-ram)
    (ld hl #x2db)
    (push af)
    (ld a 1)
    (out (5) a)
    (ld de #xc000)
    (ld bc #x52)
    (ldir)
    (pop af)
    (ld hl #x4000)
    (add hl sp)
    (ld sp hl)
    (call #xc000)
    (xor a)
    (out (5) a)
    (ld hl 0)
    (add hl sp)
    (ld bc #x4000)
    (or a)
    (sbc hl bc)
    (ld sp hl)
    ,@(pop* '(de hl af))
    (jp po local-label11)
    (ei)
    (label local-label11)
    (pop af)
    (pop bc)
    (ret)
    (label copy-sector-to-swap-ram)
    (out (7) a)
    (ld a ,swap-sector)
    (out (6) a)
    (label copy-sector-to-swap-preloop)
    (ld hl #x8000)
    (ld de #x4000)
    (ld bc #x4000)
    (label copy-sector-to-swap-loop)
    (ld a #xaa)
    (ld (#xaaa) a)
    (ld a #x55)
    (ld (#x555) a)
    (ld a #xa0)
    (ld (#xaaa) a)
    (ld a (hl))
    (ld (de) a)
    (inc de)
    (dec bc)
    (label local-label12)
    (xor (hl))
    (bit 7 a)
    (jr z local-label13)
    (bit 5 a)
    (jr z local-label12)
    (ld a #xf0)
    (ld (0) a)
    (ld a #x81)
    (out (7) a)
    (ret)
    (label local-label13)
    (inc hl)
    (ld a b)
    (or a)
    (jr nz copy-sector-to-swap-loop)
    (ld a c)
    (or a)
    (jr nz copy-sector-to-swap-loop)
    (in a (7))
    (inc a)
    
    (out (7) a)
    (in a (6))
    (inc a)
    (out (6) a)
    (and #b00000011)
    (or a)
    (jr nz copy-sector-to-swap-preloop)
    (ld a #x81)
    (out (7) a)
    (ret)
    
    (label copy-flash-page)
    (push de)
    (ld d a)
    (push af)
    (ld a i)
    (ld a i)
    (push af)
    (di)
    (ld a d)
    ,@(push* '(hl de af bc))
    ;; (ld hl copy-flash-page-ram)
    (ld hl #x36c)
    (ld a 1)
    (out (5) a)
    (ld de #xc000)
    (ld bc #x42)
    (ldir)
    (pop bc)
    (pop af)
    (ld hl #x4000)
    ;; Forgetting a byte?
    (add hl sp)
    (ld sp hl)
    (call #xc000)
    (xor a)
    (out (5) a)
    (ld hl 0)
    (add hl sp)
    (ld bc #x4000)
    (or a)
    (sbc hl bc)
    (ld sp hl)
    ,@(pop* '(de hl bc af))
    (jp po local-label14)
    (ei)
    (label local-label14)
    (pop af)
    (ret)

    (label copy-flash-page-ram)
    (out (6) a)
    (ld a b)
    (out (7) a)

    (label copy-flash-page-preloop)
    (ld hl #x8000)
    (ld de #x4000)
    (ld bc #x4000)
    (label copy-flash-page-loop)
    (ld a #xaa)
    (ld (#xaaa) a)
    (ld a #x55)
    (ld (#x555) a)
    (ld a #xa0)
    (ld (#xaaa) a)
    (ld a (hl))
    (ld (de) a)
    (inc de)
    (dec bc)
    (label local-label15)
    (xor (hl))
    (bit 7 a)
    (jr z local-label16)
    (bit 5 a)
    (jr z local-label15)
    (ld a #xf0)
    (ld (0) a)
    (ld a #x81)
    (out (7) a)
    (ret)
    (label local-label16)
    (inc hl)
    (ld a b)
    (or a)
    (jr nz copy-flash-page-loop)
    (ld a c)
    (or a)
    (jr nz copy-flash-page-loop)
    (ld a #x81)
    (out (7) a)
    (ret)
    (label copy-flash-page-ram-end)

    ;; util.asm
    (label get-battery-level)
    (push af)
    (ld b 0)
    (ld a #b00000110)
    (out (6) a)
    (in a (2))
    (bit 0 a)
    (jr z get-battery-level-done)

    (ld b 1)
    (ld a #b01000110)
    (out (6) a)
    (in a (2))
    (bit 0 a)
    (jr z get-battery-level-done)

    (ld b 2)
    (ld a #b10000110)
    (out (6) a)
    (in a (2))
    (bit 0 a)
    (jr z get-battery-level-done)

    (ld b 3)
    (ld a #b11000110)
    (out (6) a)
    (in a (2))
    (bit 0 a)
    (jr z get-battery-level-done)
    (ld b 4)
    
    (label get-battery-level-done)
    (ld a #b110)
    (out (6) a)
    (pop af)
    (ret)

    (label sleep)
    (ld a i)
    (push af)
    (ld a 2)
    (out (#x10) a)
    (di)
    (im 1)
    (ei)
    (ld a 1)
    (out (3) a)
    (halt)
    (di)
    (ld a #xb)
    (out (3) a)
    (ld a 3)
    (out (#x10) a)
    (pop af)
    (ret po)
    (ei)
    (ret)

    (label de-mul-a)
    (ld hl 0)
    (ld b 8)
    (label de-mul-loop)
    (rrca)
    (jr nc de-mul-skip)
    (add hl de)
    (label de-mul-skip)
    (sla e)
    (rl d)
    (djnz de-mul-loop)
    (ret)

    (label unlock-flash)
    (push af)
    (push bc)
    (in a (6))
    (push af)
    (ld a #x3c)
    (out (6) a)
    (ld b 1)
    (ld c #x14)
    (call #x4001)
    (pop af)
    (out (6) a)
    (pop bc)
    (pop af)
    (ret)

    (label lock-flash)
    (push af)
    (push bc)
    (in a (6))
    (push af)
    (ld a #x3c)
    (out (6) a)
    (ld b 0)
    (ld c #x14)
    (call #x4017)
    (pop af)
    (out (6) a)
    (pop bc)
    (pop af)
    (ret)

    (label cp-hl-de)
    (push hl)
    (or a)
    (sbc hl de)
    (pop hl)
    (ret)

    (label cp-hl-bc)
    (push hl)
    (or a)
    (sbc hl bc)
    (pop hl)
    (ret)

    (label cp-bc-de)
    (push hl)
    (ld h b)
    (ld l c)
    (or a)
    (sbc hl de)
    (pop hl)
    (ret)

    (label cp-de-bc)
    (push hl)
    (ld h d)
    (ld l e)
    (or a)
    (sbc hl bc)
    (pop hl)
    (ret)

    (label compare-strings)
    (ld a (de))
    (or a)
    (jr z compare-strings-eos)
    (cp (hl))
    (ret nz)
    (inc hl)
    (inc de)
    (jr compare-strings)
    (label compare-strings-eos)
    (ld a (hl))
    (or a)
    (ret)

    (label quicksort)
    ,@(push* '(hl de bc af))
    (ld hl 0)
    (push hl)
    (label qs-loop)
    (ld h b)
    (ld l c)
    (or a)
    (sbc hl de)
    (jp c next1)
    (pop bc)
    (ld a b)
    (or c)
    (jr z end-qs)
    (pop de)
    (jp qs-loop)
    
    (label next1)
    (push de)
    (push bc)
    (ld a (bc))
    (ld h a)
    (dec bc)
    (inc de)
    
    (label fleft)
    (inc bc)
    (ld a (bc))
    (cp h)
    (jp c fleft)
    
    (label fright)
    (dec de)
    (ld a (de))
    (ld l a)
    (ld a h)
    (cp l)
    (jp c fright)
    (push hl)
    (ld h d)
    (ld l e)
    (or a)
    (sbc hl bc)
    (jp c next2)
    (ld a (bc))
    (ld h a)
    (ld a (de))
    (ld (bc) a)
    (ld a h)
    (ld (de) a)
    (pop hl)
    (jp fleft)
    
    (label next2)
    (pop hl)
    (pop hl)
    (push bc)
    (ld b h)
    (ld c l)
    (jp qs-loop)
    
    (label end-qs)
    ,@(pop* '(af bc de hl))
    (ret)

    ;; display.asm
    (label clear-buffer)
    ,@(push* '(hl de bc iy))
    (pop hl)
    (ld (hl) 0)
    (ld d h)
    (ld e l)
    (inc de)
    (ld bc 767)
    (ldir)

    ,@(pop* '(bc de hl))
    (ret)

    (label buffer-to-lcd)
    (label buf-copy)
    (label fast-copy)
    (label safe-copy)
    ,@(push* '(hl bc af de))
    (ld a i)
    (push af)
    (di)
    (push iy)
    (pop hl)
    (ld c #x10)
    (ld a #x80)

    (label set-row)
    (db (#xed #x70))
    (jp m set-row)
    (out (#x10) a)
    (ld de 12)
    (ld a #x20)

    (label col)
    ;; (in f (c)) is not in the data sheet, hm.
    (db (#xed #x70))

    (jp m col)
    (out (#x10) a)
    (push af)
    (ld b 64)
    
    (label row)
    (ld a (hl))
    (label row-wait)
    (db (#xed #x70))

    (jp m row-wait)
    (out (#x11) a)
    (add hl de)
    (djnz row)
    (pop af)
    (dec h)
    (dec h)
    (dec h)
    (inc hl)
    (inc a)
    (cp #x2c)
    (jp nz col)
    (pop af)
    (jp po local-label17)
    (ei)
    
    (label local-label17)
    ,@(pop* '(de af bc hl))
    (ret)
    
    (label lcd-delay)
    (push af)
    (label local-label18)
    (in a (#x10))
    (rla)
    (jr c local-label18)
    (pop af)
    (ret)

    (label get-pixel)
    (ld h 0)
    (ld d h)
    (ld e l)
    (add hl hl)
    (add hl de)
    (add hl hl)
    (add hl hl)
    (ld e a)
    ,@(make-list 3 '(srl e))
    (add hl de)
    (push iy)
    (pop de)
    (add hl de)
    (and 7)
    (ld b a)
    (ld a #x80)
    (ret z)

    (label local-label19)
    (rrca)
    (djnz local-label19)
    (ret)
    
    (label pixel-on)
    (label set-pixel)
    ,@(with-regs-preserve (hl de af bc)
                          (call get-pixel)
                          (or (hl))
                          (ld (hl) a))
    (ret)

    (label pixel-off)
    (label reset-pixel)
    ,@(with-regs-preserve (hl de af bc)
                          (call get-pixel)
                          (cpl)
                          (and (hl))
                          (ld (hl) a))
    (ret)

    (label invert-pixel)
    (label pixel-flip)
    (label pixel-invert)
    (label flip-pixel)
    ,@(with-regs-preserve (hl de af bc)
                          (call get-pixel)
                          (xor (hl))
                          (ld (hl) a))
    (ret)

    (label draw-line)
    (label draw-line-or)
    ,@(with-regs-preserve (hl de bc af ix iy)
                          (call draw-line2))
    (ret)

    (label draw-line2)
    (ld a h)
    (cp d)
    (jp nc no-swap-x)
    ((ex de hl))

    (label no-swap-x)
    (ld a h)
    (sub d)
    (jp nc pos-x)
    (neg)
    
    (label pos-x)
    (ld b a)
    (ld a l )
    (sub e)
    (jp nc pos-y)
    (neg)

    (label pos-y)
    (ld c a)
    (ld a l)
    (ld hl ,(- (ash 1 16) 12))
    (cp e)
    (jp c line-up)
    (ld hl 12)

    (label line-up)
    (ld ix x-bit)
    (ld a b)
    (cp c)
    (jp nc x-line)
    (ld b c)
    (ld c a)
    (ld ix y-bit)

    (label x-line)
    (push hl)
    (ld a d)
    (ld d 0)
    (ld h d)
    (sla e)
    (sla e)
    (ld l e)
    (add hl de)
    (add hl de)
    (ld e a)
    (and #b00000111)
    (srl e)
    (srl e)
    (srl e)
    (add hl de)
    (push iy)
    (pop de)
    (add hl de)
    (add a a)
    (ld e a)
    (ld d 0)
    (add ix de)
    (ld e (+ 0 ix))
    (ld d (+ 1 ix))
    (push hl)
    (pop ix)
    ((ex de hl))
    (pop de)
    (push hl)
    (ld h b)
    (ld l c)
    (ld a h)
    (srl a)
    (inc b)
    (ret)
    
    (label x-bit)
    (dw ,(map (lambda (x)
                (string->symbol (format #f "draw-x~a" x)))
              (iota 8)))
    
    (label y-bit)
    (dw ,(map (lambda (y)
                (string->symbol (format #f "draw-y~a" y)))
              (iota 8)))
    

    ;; Code generation for the win!
    ,@(apply append
             (map (lambda (x)
                    (let* ((curr-label (string->symbol (format #f "draw-x~a" x)))
                           (next-label (string->symbol (format #f "draw-x~a" (modulo (1+ x) 8))))
                           (local-label (string->symbol (format #f "local-draw-x~a" x))))
                      `((label ,curr-label)
                        (set ,(- 7 x) (ix))
                        ,@(if (= 7 x) '((inc ix)) '())
                        (add a c)
                        (cp h)
                        (jp c ,local-label)
                        (add ix de)
                        (sub h)
                        (label ,local-label)
                        (djnz ,next-label)
                        (ret))))
                  (iota 8)))

    ,@(apply append
             (map (lambda (y)
                    (let* ((local-label (string->symbol (format #f "local-draw-y~a" y)))
                           (curr-label (string->symbol (format #f "draw-y~a" y)))
                           (next-local-label (string->symbol (format #f "local-draw-y~a" (modulo (1+ y) 8)))))
                      `((label ,local-label)
                        ,@(if (zero? y) '((inc ix)) '())
                        (sub h)
                        (dec b)
                        (ret z)
                        
                        (label ,curr-label)
                        (set ,(- 7 y) (ix))
                        (add ix de)
                        (add a l)
                        (cp h)
                        (jp nc ,next-local-label)
                        (djnz ,curr-label)
                        (ret))))
                  (iota 8)))

    (label put-sprite-xor)
    ,@(with-regs-preserve (af bc hl de ix)
                          (push hl)
                          (pop ix)
                          (call clip-sprite-xor))
    (ret)

    (label clip-sprite-xor)
    (ld a #b11111111)
    (ld (#x8000) a)
    (ld a e)
    (or a)
    (jp m clip-top)
    (sub 64)
    (ret nc)
    (neg)
    (cp b)
    (jr nc vert-clip-done)
    (ld b a)
    (jr vert-clip-done)
    
    (label clip-top)
    (ld a b)
    (neg)
    (sub e)
    (ret nc)
    (push af)
    (add a b)
    (ld e 0)
    (ld b e)
    (ld c a)
    (add ix bc)
    (pop af)
    (neg)
    (ld b a)
    
    (label vert-clip-done)
    (ld c 0)
    (ld a d)
    (cp ,(- (ash 1 8) 7))
    (jr nc clip-left)

    (cp 96)
    (ret nc)

    (cp 89)
    (jr c horiz-clip-done)

    (label clip-right)
    (and 7)
    (ld c a)
    (ld a #b11111111)

    (label find-right-mask)
    (add a a)
    (dec c)
    (jr nz find-right-mask)
    (ld (#x8000) a)
    (ld a d)
    (jr horiz-clip-done)

    (label clip-left)
    (and 7)
    (ld c a)
    (ld a #b11111111)

    (label find-left-mask)
    (add a a)
    (dec c)
    (jr nz find-left-mask)
    (cpl)
    (ld (#x8000) a)
    (ld a d)
    (add a 96)
    (ld c 12)

    (label horiz-clip-done)
    (ld h 0)
    (ld d h)
    (ld l e)
    (add hl hl)
    (add hl de)
    (add hl hl)
    (add hl hl)

    (ld e a)
    (srl e)
    (srl e)
    (srl e)
    (add hl de)

    (push iy)
    (pop de)
    (add hl de)

    (ld d 0)
    (ld e c)
    (sbc hl de)

    (and 7)
    (jr z aligned)
    (ld c a)
    (ld de 11)

    (label row-loop)
    (push bc)
    (ld b c)
    (ld a (#x8000))
    (and (ix))
    (ld c 0)

    (label shift-loop)
    (srl a)
    (rr c)
    (djnz shift-loop)
    (xor (hl))
    (ld (hl) a)

    (inc hl)
    (ld a c)
    (xor (hl))
    (ld (hl) a)

    (add hl de)
    (inc ix)
    (pop bc)
    (djnz row-loop)
    (ret)

    (label aligned)
    (ld de 12)

    (label put-loop)
    (ld a (+ 0 ix))
    (xor (hl))
    (ld (hl) a)
    (inc ix)
    (add hl de)
    (djnz put-loop)
    (ret)

    (label put-sprite-and)
    ,@(with-regs-preserve (af bc hl de ix)
                          (push hl)
                          (pop ix)
                          (call clip-sprite-and))
    (ret)

    (label clip-sprite-and)
    (ld a #b11111111)
    (ld (#x8000) a)
    (ld a e)
    (or a)
    (jp m clip-top2)
    (sub 64)
    (ret nc)
    (neg)
    (cp b)
    (jr nc vert-clip-done2)
    (ld b a)
    (jr vert-clip-done2)

    (label clip-top2)
    (ld a b)
    (neg)
    (sub e)
    (ret nc)
    (push af)
    (add a b)
    (ld e 0)
    (ld b e)
    (ld c a)
    (add ix bc)
    (pop af)
    (neg)
    (ld b a)

    (label vert-clip-done2)
    (ld c 0)
    (ld a d)
    (cp ,(- (ash 1 8) 7))
    (jr nc clip-left2)

    (cp 96)
    (ret nc)

    (cp 89)
    (jr c horiz-clip-done2)
    
    (label clip-right2)
    (and 7)
    (ld c a)
    (ld a #b11111111)
    
    (label find-right-mask2)
    (add a a)
    (dec c)
    (jr nz find-right-mask2)
    (ld (#x8000) a)
    (ld a d)
    (jr horiz-clip-done2)

    (label clip-left2)
    (and 7)
    (ld c a)
    (ld a #b11111111)

    (label find-left-mask2)
    (add a a)
    (dec c)
    (jr nz find-left-mask2)
    (cpl)
    (ld (#x8000) a)
    (ld a d)
    (add a 96)
    (ld c 12)

    (label horiz-clip-done2)
    (ld h 0)
    (ld d h)
    (ld l e)
    (add hl hl)
    (add hl de)
    (add hl hl)
    (add hl hl)

    (ld e a)
    (srl e)
    (srl e)
    (srl e)
    (add hl de)
    (push iy)
    (pop de)
    (add hl de)
    (ld d 0)
    (ld e c)
    (sbc hl de)

    (and 7)
    (jr z aligned2)

    (ld c a)
    (ld de 11)

    (label row-loop2)
    (push bc)
    (ld b c)
    (ld a (#x8000))
    (and (ix))
    (ld c 0)

    (label shift-loop2)
    (srl a)
    (rr c)
    (djnz shift-loop2)
    (cpl)
    (and (hl))
    (ld (hl) a)
    (inc hl)
    (ld a c)
    (cpl)
    (and (hl))
    (ld (hl) a)

    (add hl de)
    (inc ix)
    (pop bc)
    (djnz row-loop2)
    (ret)

    (label aligned2)
    (ld de 12)

    (label put-loop2)
    (ld a (+ 0 ix))
    (cpl)
    (and (hl))
    (ld (hl) a)
    (inc ix)
    (add hl de)
    (djnz put-loop2)
    (ret)

    ;; Hmm... I'm getting a pattern here but I can't seem to abstract
    ;; it.
    (label put-sprite-or)
    ,@(with-regs-preserve (af bc hl de ix)
                          (push hl)
                          (pop ix)
                          (call clip-sprite-or))
    (ret)

    (label clip-sprite-or)
    (ld a #b11111111)
    (ld (#x8000) a)
    (ld a e)
    (or a)
    (jp m clip-top3)

    (sub 64)
    (ret nc)
    (neg)
    (cp b)
    (jr nc vert-clip-done3)

    (ld b a)
    (jr vert-clip-done3)

    (label clip-top3)
    (ld a b)
    (neg)
    (sub e)
    (ret nc)
    (push af)
    (add a b)
    (ld e 0)
    (ld b e)
    (ld c a)
    
    (add ix bc)
    (pop af)
    (neg)
    (ld b a)

    (label vert-clip-done3)
    (ld c 0)
    (ld a d)

    (cp ,(- (ash 1 8) 7))
    (jr nc clip-left3)

    (cp 96)
    (ret nc)

    (cp 89)
    (jr c horiz-clip-done3)

    (label clip-right3)
    (and 7)
    (ld c a)
    (ld a #b11111111)

    (label find-right-mask3)
    (add a a)
    (dec c)
    (jr nz find-right-mask3)
    (ld (#x8000) a)
    (ld a d)
    (jr horiz-clip-done3)

    (label clip-left3)
    (and 7)
    (ld c a)
    (ld a #b11111111)

    (label find-left-mask3)
    (add a a)
    (dec c)
    (jr nz find-left-mask3)
    (cpl)
    (ld (#x8000) a)
    (ld a d)
    (add a 96)
    (ld c 12)

    (label horiz-clip-done3)
    (ld h 0)
    (ld d h)
    (ld l e)
    (add hl hl)
    (add hl de)
    (add hl hl)
    (add hl hl)
    (ld e a)
    (srl e)
    (srl e)
    (srl e)
    (add hl de)
    (push iy)
    (pop de)
    (add hl de)
    (ld d 0)
    (ld e c)
    (sbc hl de)

    (and 7)
    (jr z aligned3)
    (ld c a)
    (ld de 11)
    
    (label row-loop3)
    (push bc)
    (ld b c)
    (ld a (#x8000))
    (and (ix))
    (ld c 0)
    
    (label shift-loop3)
    (srl a)
    (rr c)
    (djnz shift-loop3)
    (or (hl))
    (ld (hl) a)
    
    (inc hl)
    (ld a c)
    (or (hl))
    (ld (hl) a)
    (add hl de)
    (inc ix)
    (pop bc)
    (djnz row-loop3)
    (ret)

    (label aligned3)
    (ld de 12)

    (label put-loop3)
    (ld a (+ 0 ix))
    (or (hl))
    (ld (hl) a)
    (inc ix)
    (add hl de)
    (djnz put-loop3)
    (ret)

    (label rectxor)
    (ld a 96)
    (sub e)
    (ret c)
    (ret z)
    (cp c)
    (jr nc local-rx1)
    (ld c a)
    (label local-rx1)
    (ld a #x40)
    (sub l)
    (ret c)
    (ret z)
    (cp b)
    (jr nc local-rx2)
    (ld b a)
    (label local-rx2)
    (xor a)
    (cp b)
    (ret z)
    (cp c)
    (ret z)
    (ld h a)
    (ld d a)

    (push bc)
    (push iy)
    (pop bc)
    (ld a l)
    (add a a)
    (add a l)
    (ld l a)
    (add hl hl)
    (add hl hl)
    (add hl bc)
    (ld a e)
    (srl e)
    (srl e)
    (srl e)
    (add hl de)
    (and #b00000111)
    (pop de)

    (ld b a)
    (add a e)
    (sub 8)
    (ld e 0)
    (jr c box-inv-skip)
    (ld e a)
    (xor a)

    (label box-inv-skip)
    (label box-inv-shift)
    (add a 8)
    (sub b)
    (ld c 0)
    (label box-inv-shift1)
    (scf)
    (rr c)
    (dec a)
    (jr nz box-inv-shift1)
    (ld a c)
    (inc b)
    (rlca)

    (label box-inv-shift2)
    (rrca)
    (djnz box-inv-shift2)

    (label box-inv-loop1)
    (push hl)
    (ld b d)
    (ld c a)
    (push de)
    (ld de 12)

    (label box-inv-loop2)
    (ld a c)
    (xor (hl))
    (ld (hl) a)
    (add hl de)
    (djnz box-inv-loop2)

    (pop de)
    (pop hl)
    (inc hl)
    (ld a e)
    (or a )
    (ret z)
    (sub 8)
    (ld e b)
    (jr c box-inv-shift)
    (ld e a)
    (ld a #b11111111)
    (jr box-inv-loop1)

    (label box-inv-end)
    (label rect-or)
    (ld a 96)
    (sub e)
    (ret c)
    (ret z)
    (cp c)
    (jr nc local-ro)
    (ld c a)
    (label local-ro)
    (ld a 64)
    (sub l)
    (ret c)
    (ret z)
    (cp b)
    (jr nc local-ro2)
    (ld b a)
    (label local-ro2)
    (xor a)
    (cp b)
    (ret z)
    (cp c)
    (ret z)
    (ld h a)
    (ld d a)
    (push bc)
    (push iy)
    (pop bc)
    (ld a l)
    (add a a)
    (add a l)
    (ld l a)
    (add hl hl)
    (add hl hl)
    (add hl bc)

    (ld a e)
    (srl e)
    (srl e)
    (srl e)
    (add hl de)
    (and #b00000111)
    (pop de)
    (ld b a)
    (add a e)
    (sub 8)
    (ld e 0)
    (jr c box-or-skip)
    (ld e a)
    (xor a)

    ;; (db ,(string "hello"))
    
    (label box-or-skip)
    (label box-or-shift)
    (add a 8)
    (sub b)
    (ld c 0)
    (label box-or-shift1)
    (scf)
    (rr c)
    (dec a)
    (jr nz box-or-shift1)
    (ld a c)
    (inc b)
    (rlca)

    (label box-or-shift2)
    (rrca)
    (djnz box-or-shift2)

    (label box-or-loop1)
    (push hl)
    (ld b d)
    (ld c a)
    (push de)
    (ld de 12)

    (label box-or-loop2)
    (ld a c)
    (or (hl))
    (ld (hl) a)
    (add hl de)
    (djnz box-or-loop2)
    (pop de)
    (pop hl)
    (inc hl)
    (ld a e)
    (or a)
    (ret z)
    (sub 8)
    (ld e b)
    (jr c box-or-shift)
    (ld e a)
    (ld a #b11111111)
    (jr box-or-loop1)
    (label box-or-end)

    (label rect-and)
    (ld a 96)
    (sub e)
    (ret c)
    (ret z)
    (cp c)
    (jr nc local-ra)
    (ld c a)
    (label local-ra)
    (ld a 64)
    (sub l)
    (ret c)
    (ret z)
    (cp b)
    (jr nc local-ra1)
    (ld b a)
    (label local-ra1)
    (xor a)
    (cp b)
    (ret z)
    (cp c)
    (ret z)
    (ld h a)
    (ld d a)
    (push bc)
    (push iy)
    (pop bc)
    (ld a l)
    (add a a)
    (add a l)
    (ld l a)
    (add hl hl)
    (add hl hl)
    (add hl bc)

    (ld a e)
    (srl e)
    (srl e)
    (srl e)
    (add hl de)
    (and #b00000111)
    (pop de)

    (ld b a)
    (add a e)
    (sub 8)
    (ld e 0)
    (jr c box-and-skip)
    (ld e a)
    (xor a)
    
    (label box-and-skip)
    (label box-and-shift)
    (add a 8)
    (sub b)
    (ld c 0)
    (label box-and-shift1)
    (scf)
    (rr c)
    (dec a)
    (jr nz box-and-shift1)
    (ld a c)
    (inc b)
    (rlca)
    (label box-and-shift2)
    (rrca)
    (djnz box-and-shift2)

    (label box-and-loop1)
    (push hl)
    (ld b d)
    (ld c a)
    (push de)
    (ld de 12)

    (label box-and-loop2)
    (ld a c)
    (cpl)
    (and (hl))
    (ld (hl) a)
    (add hl de)
    (djnz box-and-loop2)
    (pop de)
    (pop hl)
    (inc hl)
    (ld a e)
    (or a)
    (ret z)
    (sub 8)
    (ld e b)
    (jr c box-and-shift)
    (ld e a)
    (ld a #b11111111)
    (jr box-and-loop1)
    (label box-and-end)

    (label put-sprite16-xor)
    ,@(with-regs-preserve (af hl bc de ix)
                          (push hl)
                          (pop ix)
                          (ld a d)
                          (call put-sprite16-xor2))
    (ret)

    (label put-sprite16-xor2)
    (ld h 0)
    (ld l e)
    (ld d h)
    (add hl hl)
    (add hl de)
    (add hl hl)
    (add hl hl)
    (push iy)
    (pop de)
    (add hl de)
    (ld e a)
    (srl e)
    (srl e)
    (srl e)
    (ld d 0)
    (add hl de)
    (ld d h)
    (ld e l)
    (and 7)
    (jp z aligned-or)
    (ld c a)
    (ld de 12)
    (label row-loop-or)
    (push bc)
    (ld b c)
    (xor a)
    (ld d (+ ix 0))
    (ld e (+ ix 1))
    
    (label shift-loop-or)
    (srl d)
    (rr e)
    (rra)
    (djnz shift-loop-or)
    (inc hl)
    (inc hl)
    (xor (hl))
    (ld (hl) a)
    (ld a e)
    (dec hl)
    (xor (hl))
    (ld (hl) a)
    (ld a d)
    (dec hl)
    (xor (hl))
    (ld (hl) a)
    (pop bc)
    (ld de 12)
    (add hl de)
    (inc ix)
    (inc ix)
    (djnz row-loop-or)
    (ret)
    (label aligned-or)
    (ld de 11)

    (label aligned-loop-or)
    (ld a (+ ix 0))
    (xor (hl))
    (ld (hl) a)
    (ld a (+ ix 1))
    (inc hl)
    (xor (hl))
    (ld (hl) a)
    (add hl de)
    (inc ix)
    (inc ix)
    (djnz aligned-loop-or)
    (ret)

    (label put-sprite16-and)
    ,@(with-regs-preserve (af hl bc de ix)
                          (push hl)
                          (pop ix)
                          (ld a d)
                          (call put-sprite16-and2))
    (ret)

    (label put-sprite16-and2)
    (ld h 0)
    (ld l e)
    (ld d h)
    (add hl hl)
    (add hl de)
    (add hl hl)
    (add hl hl)
    (push iy)
    (pop de)
    (add hl de)
    ;; (db ,(string "hello"))

    (ld e a)
    (srl e)
    (srl e)
    (srl e)
    (ld d 0)
    (add hl de)
    (ld d h)
    (ld e l)
    (and 7)
    (jp z aligned-and)
    (ld c a)
    (ld de 12)
    
    (label row-loop-and)
    (push bc)
    (ld b c)
    (xor a)
    (ld d (+ ix 0))
    (ld e (+ ix 1))
    (label shift-loop-and)
    (srl d)
    (rr e)
    (rra)
    (djnz shift-loop-and)
    (inc hl)
    (inc hl)
    (xor (hl))
    (ld (hl) a)
    (ld a e)
    (dec hl)
    (cpl)
    (and (hl))
    (ld (hl) a)
    (ld a d)
    (dec hl)
    (cpl)
    (and (hl))
    (ld (hl) a)
    (pop bc)
    (ld de 12)
    (add hl de)
    (inc ix)
    (inc ix)
    (djnz row-loop-and)
    (ret)
    (label aligned-and)
    (ld de 11)
    (label aligned-loop-and)
    (ld a (+ ix 0))
    (cpl)
    (and (hl))
    (ld (hl) a)
    (ld a (+ ix 1))
    (inc hl)
    (cpl)
    (and (hl))
    (ld (hl) a)
    (add hl de)
    (inc ix)
    (inc ix)
    (djnz aligned-loop-and)
    (ret)
    
    (label wait-key)
    (label local-label20)
    (call get-key)
    (or a)
    (jr z local-label20)
    (ret)

    (label flush-keys)
    (push af)
    (label local-label21)
    (call get-key)
    (or a)
    (jr nz local-label21)
    (pop af)
    (ret)
    
    (label get-key)
    ,@(push* '(bc de hl))
    (label gs-getk2)
    (ld b 7)
    (label gs-getk-loop)
    (ld a 7)
    (sub b)
    (ld hl gs-keygroups)
    (ld d 0)
    (ld e a)
    (add hl de)
    (ld a (hl))
    (ld c a)
    (ld a #xff)
    (out (1) a)
    (ld a c)
    (out (1) a)
    (nop)
    (nop)
    (nop)
    (nop)
    (in a (1))

    (ld de 0)
    ,@(apply append (map (lambda (x)
                           (let ((dest (string->symbol (format #f "gs-getk-~a" x))))
                             `((cp ,x)
                               (jr z ,dest))))
                         '(254 253 251 247 239 223 191 127)))

    (label gs-getk-loopend)
    (djnz gs-getk-loop)
    (xor a)
    (ld (#x8000) a)
    (jr gs-getk-end)

    ,@(apply append (map (lambda (x)
                           (let ((dest (string->symbol (format #f "gs-getk-~a" x))))
                             `((label ,dest)
                               (inc e))))
                         '(127 191 223 239 247 251 253)))

    (label gs-getk-254)
    (push de)
    (ld a 7)
    (sub b)
    (add a a)
    (add a a)
    (add a a)
    (ld d 0)
    (ld e a)
    (ld hl gs-keygroup1)
    (add hl de)
    (pop de)
    (add hl de)
    (ld a (hl))
    (ld d a)
    (ld a (#x8000))
    (cp d)
    (jr z gs-getk-end)
    (ld a d)
    (ld (#x8000) a)

    (label gs-getk-end)
    (pop hl)
    (pop de)
    (pop bc)
    (ret)
    
    (label gs-keygroups)
    (db (#xFE #xFD #xFB #xF7 #xEF #xDF #xBF))
    (label gs-keygroup1)
    (db (#x01 #x02 #x03 #x04 #x00 #x00 #x00 #x00))
    (label gs-keygroup2)
    (db (#x09 #x0A #x0B #x0C #x0D #x00 #x0F #x00))
    (label gs-keygroup3)
    (db (#x11 #x12 #x13 #x14 #x15 #x16 #x17 #x00))
    (label gs-keygroup4)
    (db (#x19 #x1A #x1B #x1C #x1D #x1E #x1F #x20))
    (label gs-keygroup5)
    (db (#x21 #x22 #x23 #x24 #x25 #x26 #x27 #x28))
    (label gs-keygroup6)
    (db (#x00 #x2A #x2B #x2C #x2D #x2E #x2F #x30))
    (label gs-keygroup7)
    (db (#x31 #x32 #x33 #x34 #x35 #x36 #x37 #x38))
    
    ,(lambda () 
       (let ((res (assemble-expr `(db ,(make-list
                                    (- #xf0000
                                       *pc*) #xff)))))
            (set! *pc* #xf0000)
            res))
    
    ;; What the hell is this code doing at address 0xf0000?
    (db (#xc7 #xed #x57 #xea #x08 #x40 #xed #x57 #xf5 #xf3 #x3e #x01 #x00 #x00 #xed #x56))
    (db (#xf3 #xd3 #x14 #xf1 #xe0 #xfb #xc9 #xed #x57 #xea #x1e #x40 #xed #x57 #xf5 #xf3))
    (db (#xaf #x00 #x00 #xed #x56 #xf3 #xd3 #x14 #xf1 #xe0 #xfb #xc9 #x00 #xff #xff #xff))

    ,PRINT-PC
    ,(lambda () (assemble-expr `(db ,(make-list
                                      (- #x100000
                                         *pc*) #xff))))
    
    ,PRINT-PC))

(define fill-prog
  `((push hl)
    ,(lambda ()
       (assemble-expr `(db ,(make-list (- 10 *pc*) 0))))))

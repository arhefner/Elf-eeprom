#include opcodes.def
#include sysconfig.inc

            org   0100h

start:      mov   r2,00ffh              ; setup stack from 00ff in r2
            mov   r6,main

            lbr   initcall

main:       sex   r3

          #if RTC_GROUP
            out   EXP_PORT              ; make sure default expander group
            db    RTC_GROUP
          #endif

            out   RTC_PORT              ; disable RAM overlay to access ROM
            db    80h

          #if RTC_GROUP
            out   EXP_PORT              ; make sure default expander group
            db    NO_GROUP
          #endif

            sex   r2

            mark
            sep   r1

initcall:   ldi   call.1                ; address of scall
            phi   r4
            ldi   call.0
            plo   r4

            ldi   ret.1                 ; address of sret
            phi   r5
            ldi   ret.0
            plo   r5

            dec   r2                    ; sret needs to pop r6
            dec   r2

            sep   r5                    ; jump to sret

callbr:     glo   r3
            plo   r6

            lda   r6                    ; get subroutine address
            phi   r3                    ; and put into r3
            lda   r6
            plo   r3

            glo   re
            sep   r3                    ; jump to called routine

            ; Entry point for CALL here.

call:       plo   re                    ; Save D
            sex   r2

            glo   r6                    ; save last R[6] to stack
            stxd
            ghi   r6
            stxd

            ghi   r3                    ; copy R[3] to R[6]
            phi   r6

            br    callbr                ; transfer control to subroutine

retbr:      irx                         ; restore next-prior return address
            ldxa                        ;  to r6 from stack
            phi   r6
            ldx
            plo   r6

            glo   re                    ; restore d and jump to return
            sep   r3                    ;  address taken from r6

            ; Entry point for RET here.

ret:        plo   re                    ; save d and set x to 2
            sex   r2

            ghi   r6                    ; get return address from r6
            phi   r3
            glo   r6
            plo   r3

            br    retbr                 ; jump back to continuation

            end   start

#include opcodes.def
#include sysconfig.inc

#ifndef ROMBASE
#define ROMBASE   08000h
#endif

            ; Low Memory Usage

type:       equ   003ch                 ; RAM vector for console output
read:       equ   003fh                 ; RAM vector for console input

            org   0100h

start:      mov   r2,00ffh              ; setup stack from 00ff in r2
            mov   r6,main

            lbr   initcall

main:       call  setbd

            call  inmsg
            db    "Disabling RAM overlay.",13,10,0

            sex   r3

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

xfer:       ghi   re                    ; save UART timing
            phi   r8
            ani   0feh                  ; turn off echo
            phi   re

            call  read
            xri   55h
            bz    shake
            mov   rf,hskerr
            call  msg
            br    done
 
shake:      ldi   0aah
            call  type

next:       call  read
            bz    over
            call  type
            
            smi   1
            bz    cmd01
            mov   rf,cmderr
            call  msg
            br    done

cmd01:      call  read
            phi   r7
            call  type

            call  read
            plo   r7
            call  type

            call  read
            phi   rd
            call  type

            call  read
            plo   rd
            mov   ra,buffer             ; ignore address, always read
                                        ; into pre-allocated buffer
            mov   rc,r7
            dec   rc                    ; adjust loop count
            glo   rd
            call  type

readlp:     call  read

            str   ra
            inc   ra

            untl  rc,readlp

            mov   ra,buffer
            call  program

ack:        ldi   0aah
            call  type

            br    next

over:       call  read
            xri   'x'
            bz    done
            mov   rf,cmderr
            call  msg

done:       ghi   r8                    ; restore previous echo setting
            phi   re

            mark
            sep   r1

program:    mov   rc,rd                 ; calaculate last address in
            glo   rc                    ; 64-byte page
            ori   003fh
            plo   rc

            sub16 rc,rd                 ; rc = remaining bytes in page
            inc   rc

            mov   r9,rc
            sub16 rc,r7
            bge   partial
            mov   rc,r9
            br    eewrite
partial:    mov   rc,r7
eewrite:    sub16 r7,rc
            call  eewrblk
            brnz  r7,program

            rtn

eewrblk:    mov   r8,02aaah+ROMBASE
            mov   r9,05555h+ROMBASE

            ldi   0aah
            str   r9
            ldi   055h
            str   r8
            ldi   0a0h
            str   r9

            dec   rc
eewrloop:   lda   ra
            str   rd
            inc   rd
            untl  rc,eewrloop

            dec   rd
eewait:     ldn   rd
            str   r2
            ldn   rd
            xor
            bnz   eewait

            inc   rd

            rtn

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

            .align page

            ; Initialize CDP1854 UART port and set RE to indicate UART in use.
            ; This was written for the 1802/Mini but is generic to the 1854
            ; since it doesn't access the extra control register that the
            ; 1802/Mini has. This means it runs at whatever baud rate the
            ; hardware has setup since there isn't any software control on
setbd:      ; a generic 1854 implementation.

          #ifdef UART_DETECT
            BRMK  usebbang
          #endif
 
          #if UART_GROUP
            sex   r3
            out   EXP_PORT              ; make sure default expander group
            db    UART_GROUP
            sex   r2
          #endif

            inp   UART_DATA
            inp   UART_STATUS

            inp   UART_STATUS
            ani   2fh
            bnz   usebbang

            sex   r3
            out   UART_STATUS
            db    19h                   ; 8 data bits, 1 stop bit, no parity

          #if UART_GROUP
            out   EXP_PORT              ; make sure default expander group
            db    NO_GROUP
          #endif

            mov   rc,utype              ; set UART I/O vectors
            mov   rd,uread
            lbr   setio

usebbang:   lbr   btimalc

          #ifdef SET_BAUD
btimalc:    ldi   (FREQ_KHZ*5)/(SET_BAUD/25)-23
          #else

btimalc:    SEMK                      ; Make output in correct state

timersrt:   ldi   0                   ; Wait to make sure the line is idle,
timeidle:   smi   1                   ;  so we don't try to measure in the
            nop                         ;  middle of a character, we need to
            BRSP  timersrt            ;  get 256 consecutive loops without
            bnz   timeidle            ;  input asserted before this exits

timestrt:   BRMK  timestrt            ; Stall here until start bit begins

            nop                         ; Burn a half a loop's time here so
            ldi   1                   ;  that result rounds up if closer

timecnt1:   phi   re                  ; Count up in units of 9 machine cycles
timecnt2:   adi   1                   ;  per each loop, remembering the last
            lbz   timedone            ;  time that input is asserted, the
            BRSP  timecnt1            ;  very last of these will be just
            br    timecnt2            ;  before the start of the stop bit

timedone:   ldi   63                  ; Pre-load this value that we will 
            plo   re                  ;  need in the calculations later

            ghi   re                  ; Get timing loop value, subtract
            smi   23                  ;  offset of 23 counts, if less than
            bnf   timersrt            ;  this, then too low, go try again
          #endif

            bz    timegood            ; Fold both 23 and 24 into zero, this
            smi   1                   ;  adj is needed for 9600 at 1.8 Mhz

timegood:   phi   re                  ; Got a good measurement, save it

            smi   63                  ; Subtract 63 from time, if less than
            bnf   timekeep            ;  this, then keep the result as-is

timedivd:   smi   3                   ; Otherwise, divide the excess part
            inc   re                  ;  by three, adding to the 63 we saved
            bdf   timedivd            ;  earlier so results are 64-126
        
            glo   re                  ; Get result of division plus 63
            phi   re                  ;  and save over raw measurement

timekeep:   ghi   re                  ; Get final result and shift left one
            shl                         ;  bit to make room for echo flag, then
            adi   2+1                 ;  add 1 to baud rate and set echo flag

            phi   re                  ;  then store formatted result and

            mov   rc,btype            ; Store bit-bang I/O vectors
            mov   rd,bread

#ifdef FAST_UART
  #if FREQ_KHZ == 4000
    #include    fast_uart4000.asm
  #elif FREQ_KHZ == 1790 || FREQ_KHZ == 3686
    #include  fast_uart1790.asm
  #else
    #error    Fast UART not supported at this speed.
  #endif
#else
            ; The recvwait call receives a character through the serial port
            ; waiting indefinitely. This is the core of the normal read call
            ; and is only callable via SEP. This requires unpack to be called
            ; first to setup the time delay value at M(R2).

bread:      ghi   re                    ; remove echo bit from delay, get 1's
            shr                         ;  complement, and save on stack
            sdi   0
            str   r2

            smi   192                   ; if higher than 192, leave as it is
            bdf   breprep

            shl                         ; multiply excess by two and add back
            add                         ;  to value, update on stack
            str   r2

breprep:    ldi   0ffh
            plo   re

            ldn   r2                    ; get half for delay to middle of start
            shrc                        ;  bit, start delay calculation

brewait:    BRMK  brewait               ; wait here until start bit comes in,

bredely:    adi   4
            bnf   bredely               ;  jump based on first delay subtract

            shr                         ; separate bit 1 and 0 into D and DF,
            bnf   breoddc               ;  handle odd and even separately

            bnz   bretest               ; for even counts, add 2 cycles if
            br    bretest               ;  bit 1 non-zero, and 4 otherwise

breoddc:    lsnz                        ; for odd counts, add 3 cycles if
            br    bretest               ;  bit 1 non-zero, and 5 otherwise

bretest:    BRMK  bremark               ; if ef2 is asserted, is a space,

            glo   re
            shr
            br    bresave

bremark:    glo   re
            shr
            ori   128                   ; otherwise, for mark, shift a one

bresave:    plo   re

            ldn   r2
            bdf   bredely


            ; Done receiving bits

brestop:    BRSP  brestop               ; wait for stop bit

            ghi   re                    ; if echo flag clear, just return it
            shr
            bdf   btype

            glo   re
            rtn


            ; The send routine outputs the character in RE.0 through the serial
            ; interface. This requires the delay timer value to be at M(R2)
            ; which is setup by calling unpack first. This is inlined into
            ; nbread but can also be called separately using SEP.

btype:      glo   re
            stxd

            ghi   re                    ; remove echo bit from delay, get 1's
            shr                         ;  complement, and save on stack
            sdi   0
            str   r2

            smi   192                   ; if higher than 192, leave as it is
            bdf   btywait

            shl                         ; multiply excess by two and add back
            add                         ;  to value, update on stack
            str   r2



            ; Delay for the stop bit

btywait:    ldn   r2                    ; Delay for one bit time before start
            adi   40
            bdf   btystrt

btydly1:    adi   4                     ;  bit so we can be called back-to-
            bnf   btydly1               ;  back without a start bit violation

            ; Send the start bit

btystrt:    SESP

            ldn   r2                    ; Delay for one bit time before start
btydly2:    adi   4                     ;  bit so we can be called back-to-
            bnf   btydly2               ;  back without a start bit violation

            shr                         ; separate bit 1 and 0 into D and DF,
            bnf   btyodds               ;  handle odd and even separately

            bnz   btyinit               ; for even counts, add 2 cycles if
            br    btyinit               ;  bit 1 non-zero, and 4 otherwise

btyodds:    lsnz                        ; for odd counts, add 3 cycles if
            br    btyinit               ;  bit 1 non-zero, and 5 otherwise

            ; Shift a one bit into the shift register to mark end

btyinit:    glo   re
            smi   0
            shrc
            plo   re

            bdf   btymark

            ; Loop through the data bits and send

btyspac:    SESP
            SESP

btyloop:    ldn   r2                    ;  advance the stack pointer back
btydly3:    adi   4                     ;  to character value, then delay
            bnf   btydly3               ;  for one bit time

            shr                         ; separate bit 1 and 0 into D and DF,
            bnf   btyoddc               ;  handle odd and even separately

            bnz   btyshft               ; for even counts, add 2 cycles if
            br    btyshft               ;  bit 1 non-zero, and 4 otherwise

btyoddc:    lsnz                        ; for odd counts, add 3 cycles if
            br    btyshft               ;  bit 1 non-zero, and 5 otherwise

btyshft:    glo   re
            shr
            plo   re

            bnf   btyspac

btymark:    SEMK
            bnz   btyloop

            ; Retrieve saved character and return

btyretn:    inc   r2
            ldn   r2
            rtn

#endif

            ; Copy the type vector from rc and the read vector
            ; from rd to the low-RAM I/O vectors.
setio:      mov   rf,type
            ldi   0c0h
            str   rf
            inc   rf
            ghi   rc
            str   rf
            inc   rf
            glo   rc
            str   rf
            inc   rf
            ldi   0c0h
            str   rf
            inc   rf
            ghi   rd
            str   rf
            inc   rf
            glo   rd
            str   rf

            rtn

; UREAD inputs character from the 1854 UART and echos character to output
; if RE.1 bit zero is set by falling through to UTYPE54 after input.

uread:      ghi   re
            shr

          #if UART_GROUP
            sex   r3
            out   EXP_PORT
            db    UART_GROUP
            sex   r2
          #endif

ureadlp:    inp   UART_STATUS
            ani   1
            bz    ureadlp

            inp   UART_DATA

            bnf   utypert
            plo   re

            ; UTYPE outputs character in D through 1854 UART.

          #if UART_GROUP
            br    uecho

utype:      sex   r3
            out   EXP_PORT
            db    UART_GROUP
            sex   r2

uecho:      inp   UART_STATUS
          #else
utype:      inp   UART_STATUS
          #endif

            shl
            bnf   utype

            glo   re
            str   r2
            out   UART_DATA
            dec   r2

utypert:
          #if UART_GROUP
            sex   r3
            out   EXP_PORT
            db    NO_GROUP
          #endif

            rtn

            ; Convert 16-bit number in RD to ASCII hex reprensation into the
            ; buffer pointed to by RF. This calls hexout twice.

hexout4:    ldi   hexout2.0
            stxd
            ghi   rd

            br    hexout


            ; Convert 8-bit number in RD.0 to ASCII hex reprensation into the
            ; buffer pointed to by RF.

hexout2:    ldi   hexoutr.0
            stxd
            glo   rd
 
hexout:     str   r2
            shr
            shr
            shr
            shr

            smi   10
            bnf   hexskp1
            adi   'A'-'0'-10
hexskp1:    adi   '0'+10

            str   rf
            inc   rf

            lda   r2
            ani   0fh

            smi   10
            bnf   hexskp2
            adi   'A'-'0'-10
hexskp2:    adi   '0'+10

            str   rf
            inc   rf

            ldx
            plo   r3

hexoutr:    rtn

            ; Output a zero-terminated string to current console device.
            ;
            ;   IN:   RF - pointer to string to output
            ;   OUT:  RD - set to zero
            ;         RF - left just past terminating zero byte

msglp:      call  type

msg:        lda   rf                    ; load byte from message
            bnz   msglp                 ; return if last byte

            rtn


            ; Output an inline zero-terminated string to console device.
            ;
            ;   OUT:  RD - set to zero

inmsglp:    call  type

inmsg:      lda   r6
            bnz   inmsglp

            rtn

            ; Output a zero-terminated string to current console device.
            ;
            ;   IN:   RF - pointer to string to output
            ;   OUT:  RD - set to zero
            ;         RF - left just past terminating zero byte

bmsglp:     call  btype

bmsg:       lda   rf                    ; load byte from message
            bnz   bmsglp                ; return if last byte

            rtn


            ; Output an inline zero-terminated string to console device.
            ;
            ;   OUT:  RD - set to zero

binmsglp:   call  btype

binmsg:     lda   r6
            bnz   binmsglp

            rtn

hskerr:     db    'Invalid handshake.',13,10,0
cmderr:     db    'Unrecognized command.',13,10,0

buffer:     ds    512

            end   start
; ================================================================
;  CACHE MEMORY SIMULATOR
;  Toolchain : JWasm /coff  +  JWlink  +  Irvine32
;  NO INCLUDE FILE NEEDED - uses manual PROTO declarations
;  CALLING CONVENTION: STDCALL (matches Irvine32.lib symbol names)
;
;  Three mapping modes (selectable at runtime):
;    1 - Direct Mapped        (4 lines)
;    2 - Fully Associative    (4 lines, FIFO)
;    3 - Set-Associative 2way (2 sets x 2 ways, FIFO)
;
;  8-bit addresses (0-255):
;    Direct  : [tag:4][index:2][offset:2]
;    Full-A  : [tag:6][offset:2]
;    Set-A   : [tag:5][set:1][offset:2]
; ================================================================

.386
.MODEL FLAT, STDCALL
.STACK 4096

; ──────────────────────────────────────────────────────────────
;  Irvine32 procedure declarations (no .inc file needed)
; ──────────────────────────────────────────────────────────────
WriteString  PROTO                ; EDX -> null-terminated string
WriteDec     PROTO                ; EAX = unsigned 32-bit value
WriteChar    PROTO                ; AL  = character to print
ReadChar     PROTO                ; returns char in AL
Crlf         PROTO                ; prints CR+LF
ExitProcess  PROTO, dwExitCode:DWORD

; ──────────────────────────────────────────────────────────────
;  CONSTANTS
; ──────────────────────────────────────────────────────────────
CACHE_LINES  EQU  4
WAYS         EQU  2
NUM_SETS     EQU  2
INVALID_TAG  EQU  0FFh

; ──────────────────────────────────────────────────────────────
;  DATA SEGMENT
; ──────────────────────────────────────────────────────────────
.DATA

;--- Direct-Mapped cache (4 lines) ---
dm_valid     BYTE  4 DUP(0)
dm_tag       BYTE  4 DUP(INVALID_TAG)

;--- Fully-Associative cache (4 lines) ---
fa_valid     BYTE  4 DUP(0)
fa_tag       BYTE  4 DUP(INVALID_TAG)
fa_fifo      BYTE  0            ; FIFO pointer (0-3)

;--- Set-Associative 2-way (2 sets x 2 ways) ---
; flat index = set*2 + way
sa_valid     BYTE  4 DUP(0)
sa_tag       BYTE  4 DUP(INVALID_TAG)
sa_fifo      BYTE  2 DUP(0)    ; per-set FIFO bit (0 or 1)

;--- Statistics ---
total_acc    DWORD 0
total_hit    DWORD 0
total_miss   DWORD 0

;--- Active mode (1/2/3) ---
map_mode     BYTE  1

; ──────────────────────────────────────────────────────────────
;  STRING CONSTANTS  (null-terminated for WriteString)
; ──────────────────────────────────────────────────────────────
str_banner1  BYTE "============================================",0Dh,0Ah,0
str_banner2  BYTE "    CACHE MEMORY SIMULATOR  (Irvine32)     ",0Dh,0Ah,0
str_banner3  BYTE "============================================",0Dh,0Ah,0

str_menu     BYTE 0Dh,0Ah
             BYTE "[1] Choose Mapping Type",0Dh,0Ah
             BYTE "[2] Access a Memory Address",0Dh,0Ah
             BYTE "[3] Show Cache Table",0Dh,0Ah
             BYTE "[4] Show Statistics",0Dh,0Ah
             BYTE "[5] Reset Cache",0Dh,0Ah
             BYTE "[6] Exit",0Dh,0Ah
             BYTE "Choice: ",0

str_mapmenu  BYTE 0Dh,0Ah
             BYTE "Select Mapping Type:",0Dh,0Ah
             BYTE "[1] Direct Mapped",0Dh,0Ah
             BYTE "[2] Fully Associative (FIFO)",0Dh,0Ah
             BYTE "[3] Set Associative 2-way (FIFO)",0Dh,0Ah
             BYTE "Choice: ",0

str_curmodeL BYTE "Current mode: ",0
str_mode1    BYTE "Direct Mapped",0Dh,0Ah,0
str_mode2    BYTE "Fully Associative",0Dh,0Ah,0
str_mode3    BYTE "Set Associative 2-way",0Dh,0Ah,0

str_addrpmt  BYTE 0Dh,0Ah,"Enter address (0-255): ",0
str_badinput BYTE "Invalid input! Must be 0-255.",0Dh,0Ah,0
str_hit      BYTE " >>> CACHE HIT  :-)",0Dh,0Ah,0
str_miss     BYTE " >>> CACHE MISS :-(",0Dh,0Ah,0

str_addr     BYTE "  Address : ",0
str_tag      BYTE "  Tag     : ",0
str_index    BYTE "  Index   : ",0
str_set      BYTE "  Set     : ",0
str_offset   BYTE "  Offset  : ",0

; Table display strings
str_hdr_dm   BYTE 0Dh,0Ah
             BYTE "  +------+-------+-----+",0Dh,0Ah
             BYTE "  | DIRECT MAPPED CACHE |",0Dh,0Ah
             BYTE "  +------+-------+-----+",0Dh,0Ah
             BYTE "  | Line | Valid | Tag |",0Dh,0Ah
             BYTE "  +------+-------+-----+",0Dh,0Ah,0

str_hdr_fa   BYTE 0Dh,0Ah
             BYTE "  +------+-------+-----+",0Dh,0Ah
             BYTE "  | FULLY ASSOC CACHE  |",0Dh,0Ah
             BYTE "  +------+-------+-----+",0Dh,0Ah
             BYTE "  | Line | Valid | Tag |",0Dh,0Ah
             BYTE "  +------+-------+-----+",0Dh,0Ah,0

str_hdr_sa   BYTE 0Dh,0Ah
             BYTE "  +-----+-----+-------+-----+",0Dh,0Ah
             BYTE "  |  SET ASSOCIATIVE 2-WAY   |",0Dh,0Ah
             BYTE "  +-----+-----+-------+-----+",0Dh,0Ah
             BYTE "  | Set | Way | Valid | Tag |",0Dh,0Ah
             BYTE "  +-----+-----+-------+-----+",0Dh,0Ah,0

str_sep_dm   BYTE "  +------+-------+-----+",0Dh,0Ah,0
str_sep_sa   BYTE "  +-----+-----+-------+-----+",0Dh,0Ah,0

str_row_pre  BYTE "  |  ",0
str_bar      BYTE "  | ",0
str_valid_y  BYTE "  |  Yes  |  ",0
str_valid_n  BYTE "  |  No   |  -- |",0Dh,0Ah,0
str_tag_end  BYTE "  |",0Dh,0Ah,0

str_stat_hdr BYTE 0Dh,0Ah,"  ====  STATISTICS  ====",0Dh,0Ah,0
str_acc      BYTE "  Total Accesses : ",0
str_hits     BYTE "  Cache Hits     : ",0
str_misses   BYTE "  Cache Misses   : ",0
str_ratio    BYTE "  Hit Ratio      : ",0
str_pct      BYTE " %",0Dh,0Ah,0
str_reset    BYTE 0Dh,0Ah,"  Cache and statistics reset!",0Dh,0Ah,0
str_bye      BYTE 0Dh,0Ah,"  Goodbye!",0Dh,0Ah,0

; ──────────────────────────────────────────────────────────────
;  CODE SEGMENT
; ──────────────────────────────────────────────────────────────
.CODE

; ================================================================
;  MAIN
; ================================================================
main PROC
    MOV  EDX, OFFSET str_banner1
    CALL WriteString
    MOV  EDX, OFFSET str_banner2
    CALL WriteString
    MOV  EDX, OFFSET str_banner3
    CALL WriteString

main_loop:
    MOV  EDX, OFFSET str_menu
    CALL WriteString
    CALL ReadChar
    CALL Crlf

    CMP  AL, '1'
    JE   do_mode
    CMP  AL, '2'
    JE   do_access
    CMP  AL, '3'
    JE   do_show
    CMP  AL, '4'
    JE   do_stats
    CMP  AL, '5'
    JE   do_reset
    CMP  AL, '6'
    JE   do_exit
    JMP  main_loop

do_mode:
    CALL choose_mapping
    JMP  main_loop
do_access:
    CALL access_address
    JMP  main_loop
do_show:
    CALL show_cache
    JMP  main_loop
do_stats:
    CALL show_stats
    JMP  main_loop
do_reset:
    CALL reset_cache
    JMP  main_loop
do_exit:
    MOV  EDX, OFFSET str_bye
    CALL WriteString
    INVOKE ExitProcess, 0
main ENDP

; ================================================================
;  choose_mapping
; ================================================================
choose_mapping PROC
    MOV  EDX, OFFSET str_mapmenu
    CALL WriteString
    CALL ReadChar
    CALL Crlf

    CMP  AL, '1'
    JNE  cm_try2
    MOV  map_mode, 1
    JMP  cm_done
cm_try2:
    CMP  AL, '2'
    JNE  cm_try3
    MOV  map_mode, 2
    JMP  cm_done
cm_try3:
    CMP  AL, '3'
    JNE  cm_done
    MOV  map_mode, 3

cm_done:
    MOV  EDX, OFFSET str_curmodeL
    CALL WriteString

    MOVZX EAX, map_mode
    CMP  EAX, 1
    JNE  cm_chk2
    MOV  EDX, OFFSET str_mode1
    CALL WriteString
    RET
cm_chk2:
    CMP  EAX, 2
    JNE  cm_chk3
    MOV  EDX, OFFSET str_mode2
    CALL WriteString
    RET
cm_chk3:
    MOV  EDX, OFFSET str_mode3
    CALL WriteString
    RET
choose_mapping ENDP

; ================================================================
;  access_address
; ================================================================
access_address PROC
    MOV  EDX, OFFSET str_addrpmt
    CALL WriteString
    CALL read_decimal          ; result in EBX

    CMP  EBX, 0FFFFFFFFh
    JE   aa_bad
    CMP  EBX, 255
    JA   aa_bad

    MOV  EDX, OFFSET str_addr
    CALL WriteString
    MOV  EAX, EBX
    CALL WriteDec
    CALL Crlf

    MOVZX EAX, map_mode
    CMP  EAX, 1
    JE   aa_dm
    CMP  EAX, 2
    JE   aa_fa
    CALL set_access
    RET
aa_dm:
    CALL direct_access
    RET
aa_fa:
    CALL full_access
    RET
aa_bad:
    MOV  EDX, OFFSET str_badinput
    CALL WriteString
    RET
access_address ENDP

; ================================================================
;  direct_access  -  EBX = address
;  Bits: [tag:4 | index:2 | offset:2]
; ================================================================
direct_access PROC
    ; Save offset
    MOV  EAX, EBX
    AND  EAX, 3
    PUSH EAX

    ; index = (EBX >> 2) & 3
    MOV  ESI, EBX
    SHR  ESI, 2
    AND  ESI, 3

    ; tag = EBX >> 4
    MOV  ECX, EBX
    SHR  ECX, 4

    ; Print tag
    MOV  EDX, OFFSET str_tag
    CALL WriteString
    MOV  EAX, ECX
    CALL WriteDec
    CALL Crlf

    ; Print index
    MOV  EDX, OFFSET str_index
    CALL WriteString
    MOV  EAX, ESI
    CALL WriteDec
    CALL Crlf

    ; Print offset
    MOV  EDX, OFFSET str_offset
    CALL WriteString
    POP  EAX
    CALL WriteDec
    CALL Crlf

    INC  total_acc

    MOVZX EAX, BYTE PTR dm_valid[ESI]
    TEST EAX, EAX
    JZ   da_miss

    MOVZX EAX, BYTE PTR dm_tag[ESI]
    CMP  EAX, ECX
    JNE  da_miss

    ; HIT
    INC  total_hit
    MOV  EDX, OFFSET str_hit
    CALL WriteString
    RET

da_miss:
    INC  total_miss
    MOV  EDX, OFFSET str_miss
    CALL WriteString
    MOV  BYTE PTR dm_valid[ESI], 1
    MOV  BYTE PTR dm_tag[ESI], CL
    RET
direct_access ENDP

; ================================================================
;  full_access  -  EBX = address
;  Bits: [tag:6 | offset:2]   FIFO replacement
; ================================================================
full_access PROC
    MOV  ECX, EBX
    SHR  ECX, 2                ; ECX = tag

    MOV  EDX, OFFSET str_tag
    CALL WriteString
    MOV  EAX, ECX
    CALL WriteDec
    CALL Crlf

    MOV  EDX, OFFSET str_offset
    CALL WriteString
    MOV  EAX, EBX
    AND  EAX, 3
    CALL WriteDec
    CALL Crlf

    INC  total_acc

    MOV  ESI, 0
fa_srch:
    CMP  ESI, CACHE_LINES
    JGE  fa_miss

    MOVZX EAX, BYTE PTR fa_valid[ESI]
    TEST EAX, EAX
    JZ   fa_next

    MOVZX EAX, BYTE PTR fa_tag[ESI]
    CMP  EAX, ECX
    JE   fa_hit

fa_next:
    INC  ESI
    JMP  fa_srch

fa_hit:
    INC  total_hit
    MOV  EDX, OFFSET str_hit
    CALL WriteString
    RET

fa_miss:
    INC  total_miss
    MOV  EDX, OFFSET str_miss
    CALL WriteString
    MOVZX ESI, BYTE PTR fa_fifo
    MOV  BYTE PTR fa_valid[ESI], 1
    MOV  BYTE PTR fa_tag[ESI], CL
    MOVZX EAX, BYTE PTR fa_fifo
    INC  EAX
    AND  EAX, 3
    MOV  BYTE PTR fa_fifo, AL
    RET
full_access ENDP

; ================================================================
;  set_access  -  EBX = address
;  Bits: [tag:5 | set:1 | offset:2]
; ================================================================
set_access PROC
    ; set = (EBX >> 2) & 1
    MOV  EDI, EBX
    SHR  EDI, 2
    AND  EDI, 1

    ; tag = EBX >> 3
    MOV  ECX, EBX
    SHR  ECX, 3

    MOV  EDX, OFFSET str_tag
    CALL WriteString
    MOV  EAX, ECX
    CALL WriteDec
    CALL Crlf

    MOV  EDX, OFFSET str_set
    CALL WriteString
    MOV  EAX, EDI
    CALL WriteDec
    CALL Crlf

    MOV  EDX, OFFSET str_offset
    CALL WriteString
    MOV  EAX, EBX
    AND  EAX, 3
    CALL WriteDec
    CALL Crlf

    INC  total_acc

    ; base = set * 2
    MOV  ESI, EDI
    SHL  ESI, 1

    ; Check way 0
    MOVZX EAX, BYTE PTR sa_valid[ESI]
    TEST EAX, EAX
    JZ   sa_way1
    MOVZX EAX, BYTE PTR sa_tag[ESI]
    CMP  EAX, ECX
    JE   sa_hit

sa_way1:
    MOV  EBX, ESI
    INC  EBX
    MOVZX EAX, BYTE PTR sa_valid[EBX]
    TEST EAX, EAX
    JZ   sa_miss
    MOVZX EAX, BYTE PTR sa_tag[EBX]
    CMP  EAX, ECX
    JE   sa_hit

sa_miss:
    INC  total_miss
    MOV  EDX, OFFSET str_miss
    CALL WriteString
    MOVZX EAX, BYTE PTR sa_fifo[EDI]
    MOV  EBX, ESI
    ADD  EBX, EAX
    MOV  BYTE PTR sa_valid[EBX], 1
    MOV  BYTE PTR sa_tag[EBX], CL
    XOR  BYTE PTR sa_fifo[EDI], 1
    RET

sa_hit:
    INC  total_hit
    MOV  EDX, OFFSET str_hit
    CALL WriteString
    RET
set_access ENDP

; ================================================================
;  show_cache
; ================================================================
show_cache PROC
    MOVZX EAX, map_mode
    CMP  EAX, 1
    JE   sc_dm
    CMP  EAX, 2
    JE   sc_fa
    JMP  sc_sa

sc_dm:
    MOV  EDX, OFFSET str_hdr_dm
    CALL WriteString
    MOV  ESI, 0
sc_dm_lp:
    CMP  ESI, CACHE_LINES
    JGE  sc_dm_end
    MOV  EDX, OFFSET str_row_pre
    CALL WriteString
    MOV  EAX, ESI
    CALL WriteDec
    MOVZX EAX, BYTE PTR dm_valid[ESI]
    CMP  EAX, 1
    JNE  sc_dm_no
    MOV  EDX, OFFSET str_valid_y
    CALL WriteString
    MOVZX EAX, BYTE PTR dm_tag[ESI]
    CALL WriteDec
    MOV  EDX, OFFSET str_tag_end
    CALL WriteString
    INC  ESI
    JMP  sc_dm_lp
sc_dm_no:
    MOV  EDX, OFFSET str_valid_n
    CALL WriteString
    INC  ESI
    JMP  sc_dm_lp
sc_dm_end:
    MOV  EDX, OFFSET str_sep_dm
    CALL WriteString
    RET

sc_fa:
    MOV  EDX, OFFSET str_hdr_fa
    CALL WriteString
    MOV  ESI, 0
sc_fa_lp:
    CMP  ESI, CACHE_LINES
    JGE  sc_fa_end
    MOV  EDX, OFFSET str_row_pre
    CALL WriteString
    MOV  EAX, ESI
    CALL WriteDec
    MOVZX EAX, BYTE PTR fa_valid[ESI]
    CMP  EAX, 1
    JNE  sc_fa_no
    MOV  EDX, OFFSET str_valid_y
    CALL WriteString
    MOVZX EAX, BYTE PTR fa_tag[ESI]
    CALL WriteDec
    MOV  EDX, OFFSET str_tag_end
    CALL WriteString
    INC  ESI
    JMP  sc_fa_lp
sc_fa_no:
    MOV  EDX, OFFSET str_valid_n
    CALL WriteString
    INC  ESI
    JMP  sc_fa_lp
sc_fa_end:
    MOV  EDX, OFFSET str_sep_dm
    CALL WriteString
    RET

sc_sa:
    MOV  EDX, OFFSET str_hdr_sa
    CALL WriteString
    MOV  EDI, 0
sc_sa_set:
    CMP  EDI, NUM_SETS
    JGE  sc_sa_end
    MOV  ESI, 0
sc_sa_way:
    CMP  ESI, WAYS
    JGE  sc_sa_nxt_set
    MOV  EBX, EDI
    SHL  EBX, 1
    ADD  EBX, ESI
    MOV  EDX, OFFSET str_bar
    CALL WriteString
    MOV  EAX, EDI
    CALL WriteDec
    MOV  EDX, OFFSET str_bar
    CALL WriteString
    MOV  EAX, ESI
    CALL WriteDec
    MOVZX EAX, BYTE PTR sa_valid[EBX]
    CMP  EAX, 1
    JNE  sc_sa_no
    MOV  EDX, OFFSET str_valid_y
    CALL WriteString
    MOVZX EAX, BYTE PTR sa_tag[EBX]
    CALL WriteDec
    MOV  EDX, OFFSET str_tag_end
    CALL WriteString
    INC  ESI
    JMP  sc_sa_way
sc_sa_no:
    MOV  EDX, OFFSET str_valid_n
    CALL WriteString
    INC  ESI
    JMP  sc_sa_way
sc_sa_nxt_set:
    INC  EDI
    JMP  sc_sa_set
sc_sa_end:
    MOV  EDX, OFFSET str_sep_sa
    CALL WriteString
    RET
show_cache ENDP

; ================================================================
;  show_stats
; ================================================================
show_stats PROC
    MOV  EDX, OFFSET str_stat_hdr
    CALL WriteString
    MOV  EDX, OFFSET str_acc
    CALL WriteString
    MOV  EAX, total_acc
    CALL WriteDec
    CALL Crlf
    MOV  EDX, OFFSET str_hits
    CALL WriteString
    MOV  EAX, total_hit
    CALL WriteDec
    CALL Crlf
    MOV  EDX, OFFSET str_misses
    CALL WriteString
    MOV  EAX, total_miss
    CALL WriteDec
    CALL Crlf
    MOV  EDX, OFFSET str_ratio
    CALL WriteString
    MOV  EAX, total_acc
    TEST EAX, EAX
    JZ   ss_zero
    MOV  EAX, total_hit
    MOV  EBX, 100
    MUL  EBX
    MOV  EBX, total_acc
    DIV  EBX
    CALL WriteDec
    JMP  ss_pct
ss_zero:
    MOV  AL, '0'
    CALL WriteChar
ss_pct:
    MOV  EDX, OFFSET str_pct
    CALL WriteString
    RET
show_stats ENDP

; ================================================================
;  reset_cache
; ================================================================
reset_cache PROC
    MOV  ECX, CACHE_LINES
    MOV  ESI, 0
rc1:
    MOV  BYTE PTR dm_valid[ESI], 0
    MOV  BYTE PTR dm_tag[ESI], INVALID_TAG
    INC  ESI
    LOOP rc1

    MOV  ECX, CACHE_LINES
    MOV  ESI, 0
rc2:
    MOV  BYTE PTR fa_valid[ESI], 0
    MOV  BYTE PTR fa_tag[ESI], INVALID_TAG
    INC  ESI
    LOOP rc2
    MOV  BYTE PTR fa_fifo, 0

    MOV  ECX, 4
    MOV  ESI, 0
rc3:
    MOV  BYTE PTR sa_valid[ESI], 0
    MOV  BYTE PTR sa_tag[ESI], INVALID_TAG
    INC  ESI
    LOOP rc3
    MOV  BYTE PTR sa_fifo[0], 0
    MOV  BYTE PTR sa_fifo[1], 0

    MOV  total_acc,  0
    MOV  total_hit,  0
    MOV  total_miss, 0

    MOV  EDX, OFFSET str_reset
    CALL WriteString
    RET
reset_cache ENDP

; ================================================================
;  read_decimal  -  reads digits, returns value in EBX
;  EBX = 0FFFFFFFFh on invalid input
; ================================================================
read_decimal PROC
    MOV  EBX, 0
    MOV  ECX, 0

rd_key:
    CALL ReadChar
    CMP  AL, 0Dh
    JE   rd_done
    CMP  AL, '0'
    JB   rd_invalid
    CMP  AL, '9'
    JA   rd_invalid

    CALL WriteChar             ; echo digit

    MOVZX EAX, AL
    SUB  EAX, '0'
    PUSH EAX
    MOV  EAX, EBX
    MOV  EDX, 10
    MUL  EDX
    POP  EDX
    ADD  EAX, EDX
    MOV  EBX, EAX

    INC  ECX
    CMP  ECX, 3
    JL   rd_key

rd_flush:
    CALL ReadChar
    CMP  AL, 0Dh
    JNE  rd_flush
    JMP  rd_done

rd_invalid:
    MOV  EBX, 0FFFFFFFFh

rd_done:
    CALL Crlf
    RET
read_decimal ENDP

END main
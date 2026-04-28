; ============================================================
;  CACHE MEMORY SIMULATOR
;  Language  : x86 Assembly (MASM/TASM compatible)
;  Target    : DOS (INT 21h), 16-bit real mode
;  Assembled : TASM cache_simulator.asm  (or MASM)
;              TLINK cache_simulator.obj
;              cache_simulator.exe
;
;  Mapping modes supported
;    1. Direct Mapped  (4-line cache, line = addr MOD 4)
;    2. Fully Associative  (4-line cache, FIFO replacement)
;    3. Set Associative 2-way  (2 sets x 2 ways, FIFO)
;
;  Address format (8-bit simplified)
;    Direct  :  [ tag 4-bit | index 2-bit | offset 2-bit ]
;    Full A. :  [ tag 6-bit | offset 2-bit ]
;    Set A.  :  [ tag 5-bit | set 1-bit | offset 2-bit ]
; ============================================================

.MODEL SMALL
.STACK 200h

; ─────────────────────────────────────────────────────────────
;  CONSTANTS
; ─────────────────────────────────────────────────────────────
CACHE_LINES   EQU  4          ; total cache lines
WAYS          EQU  2          ; ways for set-associative
NUM_SETS      EQU  2          ; sets for set-associative (CACHE_LINES/WAYS)
OFFSET_BITS   EQU  2          ; bits for block offset
INDEX_BITS    EQU  2          ; bits for direct-map index
SET_BITS      EQU  1          ; bits for set-associative set index
INVALID       EQU  0FFh       ; sentinel = empty cache line

; ─────────────────────────────────────────────────────────────
;  DATA SEGMENT
; ─────────────────────────────────────────────────────────────
.DATA

; ---------- Direct-map cache (4 lines) ----------
; Each entry: valid(1 byte) + tag(1 byte)
dm_valid   DB  4 DUP(0)       ; 0 = invalid, 1 = valid
dm_tag     DB  4 DUP(INVALID)

; ---------- Fully-associative cache (4 lines) ----------
fa_valid   DB  4 DUP(0)
fa_tag     DB  4 DUP(INVALID)
fa_fifo    DB  0              ; next victim pointer (0-3)

; ---------- Set-associative cache (2 sets x 2 ways) ----------
; sa_valid[set][way], sa_tag[set][way], sa_fifo[set]
sa_valid   DB  4 DUP(0)       ; [set0w0,set0w1,set1w0,set1w1]
sa_tag     DB  4 DUP(INVALID)
sa_fifo    DB  2 DUP(0)       ; per-set FIFO pointer

; ---------- Statistics ----------
total_acc  DW  0
total_hit  DW  0
total_miss DW  0

; ---------- Current mapping mode (1/2/3) ----------
map_mode   DB  1

; ---------- String messages ----------
crlf       DB  0Dh,0Ah,'$'
banner     DB  '============================================',0Dh,0Ah
           DB  '     CACHE MEMORY SIMULATOR (x86 ASM)      ',0Dh,0Ah
           DB  '============================================',0Dh,0Ah,'$'
main_menu  DB  0Dh,0Ah
           DB  '[1] Choose Mapping Type',0Dh,0Ah
           DB  '[2] Access a Memory Address',0Dh,0Ah
           DB  '[3] Show Cache Table',0Dh,0Ah
           DB  '[4] Show Statistics',0Dh,0Ah
           DB  '[5] Reset Cache',0Dh,0Ah
           DB  '[6] Exit',0Dh,0Ah
           DB  'Choice: $'
map_menu   DB  0Dh,0Ah
           DB  'Mapping Type:',0Dh,0Ah
           DB  '[1] Direct Mapped',0Dh,0Ah
           DB  '[2] Fully Associative (FIFO)',0Dh,0Ah
           DB  '[3] Set Associative 2-way (FIFO)',0Dh,0Ah
           DB  'Choice: $'
cur_mode   DB  0Dh,0Ah,'Current mode: $'
mode1_str  DB  'Direct Mapped',0Dh,0Ah,'$'
mode2_str  DB  'Fully Associative',0Dh,0Ah,'$'
mode3_str  DB  'Set Associative 2-way',0Dh,0Ah,'$'
addr_prompt DB 0Dh,0Ah,'Enter address (0-255 decimal): $'
invalid_msg DB 0Dh,0Ah,'Invalid input!',0Dh,0Ah,'$'
hit_msg    DB  ' >> CACHE HIT  :-)',0Dh,0Ah,'$'
miss_msg   DB  ' >> CACHE MISS :-(',0Dh,0Ah,'$'
addr_msg   DB  0Dh,0Ah,'Address : $'
tag_msg    DB  '  Tag    : $'
idx_msg    DB  '  Index  : $'
set_msg    DB  '  Set    : $'
off_msg    DB  '  Offset : $'
sep_line   DB  '--------------------------------------------',0Dh,0Ah,'$'
tbl_hdr_dm DB  0Dh,0Ah,'  DIRECT-MAP CACHE TABLE',0Dh,0Ah
           DB  '  Line | Valid | Tag',0Dh,0Ah
           DB  '  -----+-------+----',0Dh,0Ah,'$'
tbl_hdr_fa DB  0Dh,0Ah,'  FULLY-ASSOCIATIVE CACHE TABLE',0Dh,0Ah
           DB  '  Line | Valid | Tag',0Dh,0Ah
           DB  '  -----+-------+----',0Dh,0Ah,'$'
tbl_hdr_sa DB  0Dh,0Ah,'  SET-ASSOCIATIVE CACHE TABLE (2-way)',0Dh,0Ah
           DB  '  Set|Way| Valid | Tag',0Dh,0Ah
           DB  '  ---+---+-------+----',0Dh,0Ah,'$'
line_pre   DB  '    $'
bar        DB  ' |  $'
bar2       DB  '  | $'
valid_y    DB  ' Yes  |  $'
valid_n    DB  ' No   |  $'
stat_hdr   DB  0Dh,0Ah,'  ===  STATISTICS  ===',0Dh,0Ah,'$'
stat_acc   DB  '  Total Accesses : $'
stat_hit   DB  '  Cache Hits     : $'
stat_mis   DB  '  Cache Misses   : $'
stat_rat   DB  '  Hit Ratio      : $'
percent    DB  ' %',0Dh,0Ah,'$'
reset_msg  DB  0Dh,0Ah,'Cache reset!',0Dh,0Ah,'$'
bye_msg    DB  0Dh,0Ah,'Goodbye!',0Dh,0Ah,'$'
set_pre    DB  '    $'

; ─────────────────────────────────────────────────────────────
;  CODE SEGMENT
; ─────────────────────────────────────────────────────────────
.CODE

; ============================================================
;  MAIN
; ============================================================
main PROC
    MOV  AX, @DATA
    MOV  DS, AX
    MOV  ES, AX

    ; Print banner
    LEA  DX, banner
    CALL print_str

main_loop:
    LEA  DX, main_menu
    CALL print_str
    CALL read_char          ; AX = char entered

    CMP  AL, '1'
    JE   do_choose_mode
    CMP  AL, '2'
    JE   do_access
    CMP  AL, '3'
    JE   do_show_cache
    CMP  AL, '4'
    JE   do_stats
    CMP  AL, '5'
    JE   do_reset
    CMP  AL, '6'
    JE   do_exit
    JMP  main_loop

do_choose_mode:
    CALL choose_mapping
    JMP  main_loop
do_access:
    CALL access_address
    JMP  main_loop
do_show_cache:
    CALL show_cache
    JMP  main_loop
do_stats:
    CALL show_statistics
    JMP  main_loop
do_reset:
    CALL reset_cache
    JMP  main_loop
do_exit:
    LEA  DX, bye_msg
    CALL print_str
    MOV  AX, 4C00h
    INT  21h
main ENDP

; ============================================================
;  PROCEDURE: choose_mapping
;  Lets user pick Direct / Fully-Associative / Set-Associative
; ============================================================
choose_mapping PROC
    LEA  DX, map_menu
    CALL print_str
    CALL read_char

    CMP  AL, '1'
    JE   cm_direct
    CMP  AL, '2'
    JE   cm_full
    CMP  AL, '3'
    JE   cm_set
    JMP  cm_done

cm_direct:
    MOV  map_mode, 1
    JMP  cm_done
cm_full:
    MOV  map_mode, 2
    JMP  cm_done
cm_set:
    MOV  map_mode, 3

cm_done:
    LEA  DX, cur_mode
    CALL print_str
    MOV  AL, map_mode
    CMP  AL, 1
    JNE  cm_not1
    LEA  DX, mode1_str
    CALL print_str
    JMP  cm_ret
cm_not1:
    CMP  AL, 2
    JNE  cm_not2
    LEA  DX, mode2_str
    CALL print_str
    JMP  cm_ret
cm_not2:
    LEA  DX, mode3_str
    CALL print_str
cm_ret:
    RET
choose_mapping ENDP

; ============================================================
;  PROCEDURE: access_address
;  Read address, decode, check cache, update stats
; ============================================================
access_address PROC
    LEA  DX, addr_prompt
    CALL print_str

    CALL read_decimal       ; returns value in BX (0-255)
    CMP  BX, 255
    JA   aa_invalid
    CMP  BX, 0
    JL   aa_invalid

    ; Print address
    LEA  DX, addr_msg
    CALL print_str
    MOV  AX, BX
    CALL print_decimal

    ; Dispatch to correct mapping
    MOV  AL, map_mode
    CMP  AL, 1
    JE   aa_direct
    CMP  AL, 2
    JE   aa_full
    JMP  aa_set

aa_direct:
    CALL direct_access
    JMP  aa_ret
aa_full:
    CALL full_access
    JMP  aa_ret
aa_set:
    CALL set_access
    JMP  aa_ret

aa_invalid:
    LEA  DX, invalid_msg
    CALL print_str
aa_ret:
    RET
access_address ENDP

; ============================================================
;  PROCEDURE: direct_access
;  BX = 8-bit address
;  Layout: [ tag(4) | index(2) | offset(2) ]
; ============================================================
direct_access PROC
    ; Extract fields from BX
    ; offset = BX AND 03h
    MOV  AX, BX
    AND  AX, 03h
    MOV  DI, AX            ; DI = offset

    ; index = (BX >> 2) AND 03h
    MOV  AX, BX
    SHR  AX, 2
    AND  AX, 03h
    MOV  SI, AX            ; SI = index (0-3)

    ; tag = BX >> 4
    MOV  AX, BX
    SHR  AX, 4
    MOV  CX, AX            ; CX = tag

    ; Print fields
    LEA  DX, tag_msg
    CALL print_str
    MOV  AX, CX
    CALL print_decimal

    LEA  DX, idx_msg
    CALL print_str
    MOV  AX, SI
    CALL print_decimal

    LEA  DX, off_msg
    CALL print_str
    MOV  AX, DI
    CALL print_decimal

    ; Increment total accesses
    INC  total_acc

    ; Check valid bit at dm_valid[SI]
    MOV  BX, SI
    MOV  AL, dm_valid[BX]
    CMP  AL, 0
    JE   dm_miss            ; not valid = miss

    ; Valid – compare tags
    MOV  AL, dm_tag[BX]
    CMP  AL, CL
    JNE  dm_miss

    ; HIT
    INC  total_hit
    LEA  DX, hit_msg
    CALL print_str
    JMP  dm_ret

dm_miss:
    INC  total_miss
    LEA  DX, miss_msg
    CALL print_str
    ; Load block: set valid, store tag
    MOV  BX, SI
    MOV  dm_valid[BX], 1
    MOV  dm_tag[BX], CL

dm_ret:
    RET
direct_access ENDP

; ============================================================
;  PROCEDURE: full_access
;  BX = 8-bit address
;  Layout: [ tag(6) | offset(2) ]
;  Replacement: FIFO (fa_fifo pointer)
; ============================================================
full_access PROC
    ; offset = BX AND 03h
    MOV  AX, BX
    AND  AX, 03h
    MOV  DI, AX

    ; tag = BX >> 2  (6 bits)
    MOV  AX, BX
    SHR  AX, 2
    MOV  CX, AX            ; CX = tag

    LEA  DX, tag_msg
    CALL print_str
    MOV  AX, CX
    CALL print_decimal

    LEA  DX, off_msg
    CALL print_str
    MOV  AX, DI
    CALL print_decimal

    INC  total_acc

    ; Search all 4 lines
    MOV  SI, 0
fa_search:
    CMP  SI, CACHE_LINES
    JGE  fa_miss

    MOV  BX, SI
    MOV  AL, fa_valid[BX]
    CMP  AL, 0
    JE   fa_next            ; not valid, skip

    MOV  AL, fa_tag[BX]
    CMP  AL, CL
    JE   fa_hit

fa_next:
    INC  SI
    JMP  fa_search

fa_hit:
    INC  total_hit
    LEA  DX, hit_msg
    CALL print_str
    JMP  fa_ret

fa_miss:
    INC  total_miss
    LEA  DX, miss_msg
    CALL print_str
    ; Replace FIFO slot
    MOV  AL, fa_fifo
    MOVZX BX, AL
    MOV  fa_valid[BX], 1
    MOV  fa_tag[BX], CL
    ; Advance FIFO pointer
    INC  AL
    AND  AL, 03h           ; mod 4
    MOV  fa_fifo, AL

fa_ret:
    RET
full_access ENDP

; ============================================================
;  PROCEDURE: set_access
;  BX = 8-bit address
;  Layout: [ tag(5) | set(1) | offset(2) ]
;  2 sets x 2 ways, FIFO per set
; ============================================================
set_access PROC
    ; offset = BX AND 03h
    MOV  AX, BX
    AND  AX, 03h
    MOV  DI, AX

    ; set = (BX >> 2) AND 01h
    MOV  AX, BX
    SHR  AX, 2
    AND  AX, 01h
    MOV  SI, AX            ; SI = set (0 or 1)

    ; tag = BX >> 3
    MOV  AX, BX
    SHR  AX, 3
    MOV  CX, AX            ; CX = tag

    LEA  DX, tag_msg
    CALL print_str
    MOV  AX, CX
    CALL print_decimal

    LEA  DX, set_msg
    CALL print_str
    MOV  AX, SI
    CALL print_decimal

    LEA  DX, off_msg
    CALL print_str
    MOV  AX, DI
    CALL print_decimal

    INC  total_acc

    ; base index into sa arrays = SI * WAYS  (SI*2)
    MOV  AX, SI
    SHL  AX, 1             ; AX = set * 2
    MOV  BX, AX            ; BX = base offset in sa_valid / sa_tag

    ; Check way 0
    MOV  AL, sa_valid[BX]
    CMP  AL, 0
    JE   sa_way1
    MOV  AL, sa_tag[BX]
    CMP  AL, CL
    JE   sa_hit

sa_way1:
    ; Check way 1
    MOV  AX, BX
    INC  AX
    MOV  DX, AX            ; DX = BX+1
    MOV  AL, sa_valid[DX]
    CMP  AL, 0
    JE   sa_miss
    MOV  AL, sa_tag[DX]
    CMP  AL, CL
    JE   sa_hit

sa_miss:
    INC  total_miss
    LEA  DX, miss_msg
    CALL print_str
    ; FIFO replacement within set
    ; sa_fifo[SI] tells which way to evict (0 or 1)
    MOV  AX, SI
    MOV  DI, AX            ; DI = set index for fifo
    MOV  AL, sa_fifo[DI]   ; AL = victim way (0 or 1)
    MOVZX AX, AL
    ; absolute index = set*2 + way
    MOV  BX, SI
    SHL  BX, 1
    ADD  BX, AX            ; BX = absolute index
    MOV  sa_valid[BX], 1
    MOV  sa_tag[BX], CL
    ; flip fifo pointer for this set
    MOV  AX, SI
    XOR  sa_fifo[AX], 1
    JMP  sa_ret

sa_hit:
    INC  total_hit
    LEA  DX, hit_msg
    CALL print_str

sa_ret:
    RET
set_access ENDP

; ============================================================
;  PROCEDURE: show_cache
;  Prints current cache table based on active mode
; ============================================================
show_cache PROC
    MOV  AL, map_mode
    CMP  AL, 1
    JE   sc_direct
    CMP  AL, 2
    JE   sc_full
    JMP  sc_set

sc_direct:
    LEA  DX, tbl_hdr_dm
    CALL print_str
    MOV  SI, 0
sc_dm_loop:
    CMP  SI, CACHE_LINES
    JGE  sc_ret

    ; Print "    "
    LEA  DX, line_pre
    CALL print_str
    ; Print line number
    MOV  AX, SI
    CALL print_decimal
    ; Print " |  "
    LEA  DX, bar
    CALL print_str
    ; Print valid
    MOV  BX, SI
    MOV  AL, dm_valid[BX]
    CMP  AL, 1
    JE   sc_dm_yes
    LEA  DX, valid_n
    CALL print_str
    JMP  sc_dm_tag
sc_dm_yes:
    LEA  DX, valid_y
    CALL print_str
sc_dm_tag:
    ; Print tag
    MOV  BX, SI
    MOV  AL, dm_tag[BX]
    CMP  BYTE PTR dm_valid[BX], 1
    JE   sc_dm_print_tag
    MOV  AX, 0FFFFh        ; show -- for empty
    JMP  sc_dm_tagout
sc_dm_print_tag:
    MOVZX AX, AL
sc_dm_tagout:
    CMP  AX, 0FFFFh
    JE   sc_dm_dash
    CALL print_decimal
    JMP  sc_dm_nl
sc_dm_dash:
    MOV  DL, '-'
    MOV  AH, 02h
    INT  21h
    MOV  DL, '-'
    INT  21h
sc_dm_nl:
    LEA  DX, crlf
    CALL print_str

    INC  SI
    JMP  sc_dm_loop

sc_full:
    LEA  DX, tbl_hdr_fa
    CALL print_str
    MOV  SI, 0
sc_fa_loop:
    CMP  SI, CACHE_LINES
    JGE  sc_ret
    LEA  DX, line_pre
    CALL print_str
    MOV  AX, SI
    CALL print_decimal
    LEA  DX, bar
    CALL print_str
    MOV  BX, SI
    MOV  AL, fa_valid[BX]
    CMP  AL, 1
    JE   sc_fa_yes
    LEA  DX, valid_n
    CALL print_str
    JMP  sc_fa_tag
sc_fa_yes:
    LEA  DX, valid_y
    CALL print_str
sc_fa_tag:
    MOV  BX, SI
    CMP  BYTE PTR fa_valid[BX], 1
    JNE  sc_fa_dash
    MOV  AL, fa_tag[BX]
    MOVZX AX, AL
    CALL print_decimal
    JMP  sc_fa_nl
sc_fa_dash:
    MOV  DL, '-'
    MOV  AH, 02h
    INT  21h
    MOV  DL, '-'
    INT  21h
sc_fa_nl:
    LEA  DX, crlf
    CALL print_str
    INC  SI
    JMP  sc_fa_loop

sc_set:
    LEA  DX, tbl_hdr_sa
    CALL print_str
    ; Loop over sets then ways
    MOV  SI, 0             ; SI = set
sc_sa_set_loop:
    CMP  SI, NUM_SETS
    JGE  sc_ret
    MOV  DI, 0             ; DI = way
sc_sa_way_loop:
    CMP  DI, WAYS
    JGE  sc_sa_next_set

    LEA  DX, set_pre
    CALL print_str
    ; print set
    MOV  AX, SI
    CALL print_decimal
    LEA  DX, bar2
    CALL print_str
    ; print way
    MOV  AX, DI
    CALL print_decimal
    LEA  DX, bar
    CALL print_str

    ; Absolute index = SI*2 + DI
    MOV  AX, SI
    SHL  AX, 1
    ADD  AX, DI
    MOV  BX, AX

    MOV  AL, sa_valid[BX]
    CMP  AL, 1
    JE   sc_sa_yes
    LEA  DX, valid_n
    CALL print_str
    JMP  sc_sa_tag
sc_sa_yes:
    LEA  DX, valid_y
    CALL print_str
sc_sa_tag:
    MOV  AX, SI
    SHL  AX, 1
    ADD  AX, DI
    MOV  BX, AX
    CMP  BYTE PTR sa_valid[BX], 1
    JNE  sc_sa_dash
    MOV  AL, sa_tag[BX]
    MOVZX AX, AL
    CALL print_decimal
    JMP  sc_sa_nl
sc_sa_dash:
    MOV  DL, '-'
    MOV  AH, 02h
    INT  21h
    MOV  DL, '-'
    INT  21h
sc_sa_nl:
    LEA  DX, crlf
    CALL print_str
    INC  DI
    JMP  sc_sa_way_loop

sc_sa_next_set:
    INC  SI
    JMP  sc_sa_set_loop

sc_ret:
    RET
show_cache ENDP

; ============================================================
;  PROCEDURE: show_statistics
; ============================================================
show_statistics PROC
    LEA  DX, stat_hdr
    CALL print_str

    LEA  DX, stat_acc
    CALL print_str
    MOV  AX, total_acc
    CALL print_decimal
    LEA  DX, crlf
    CALL print_str

    LEA  DX, stat_hit
    CALL print_str
    MOV  AX, total_hit
    CALL print_decimal
    LEA  DX, crlf
    CALL print_str

    LEA  DX, stat_mis
    CALL print_str
    MOV  AX, total_miss
    CALL print_decimal
    LEA  DX, crlf
    CALL print_str

    ; Hit ratio = (hits * 100) / total  (integer %)
    LEA  DX, stat_rat
    CALL print_str
    MOV  AX, total_acc
    CMP  AX, 0
    JE   ss_zero_ratio
    MOV  AX, total_hit
    MOV  BX, 100
    MUL  BX                ; DX:AX = hits * 100
    MOV  BX, total_acc
    DIV  BX                ; AX = percentage
    CALL print_decimal
    JMP  ss_pct
ss_zero_ratio:
    MOV  DL, '0'
    MOV  AH, 02h
    INT  21h
ss_pct:
    LEA  DX, percent
    CALL print_str
    RET
show_statistics ENDP

; ============================================================
;  PROCEDURE: reset_cache
;  Clears all cache arrays and statistics
; ============================================================
reset_cache PROC
    ; Zero direct-map
    MOV  CX, CACHE_LINES
    MOV  SI, 0
rc_dm:
    MOV  dm_valid[SI], 0
    MOV  dm_tag[SI],   INVALID
    INC  SI
    LOOP rc_dm

    ; Zero fully-associative
    MOV  CX, CACHE_LINES
    MOV  SI, 0
rc_fa:
    MOV  fa_valid[SI], 0
    MOV  fa_tag[SI],   INVALID
    INC  SI
    LOOP rc_fa
    MOV  fa_fifo, 0

    ; Zero set-associative
    MOV  CX, 4             ; CACHE_LINES entries
    MOV  SI, 0
rc_sa:
    MOV  sa_valid[SI], 0
    MOV  sa_tag[SI],   INVALID
    INC  SI
    LOOP rc_sa
    MOV  sa_fifo[0], 0
    MOV  sa_fifo[1], 0

    ; Reset statistics
    MOV  total_acc, 0
    MOV  total_hit, 0
    MOV  total_miss, 0

    LEA  DX, reset_msg
    CALL print_str
    RET
reset_cache ENDP

; ============================================================
;  UTILITY: print_str
;  DX = offset of '$'-terminated string
; ============================================================
print_str PROC
    MOV  AH, 09h
    INT  21h
    RET
print_str ENDP

; ============================================================
;  UTILITY: read_char
;  Returns pressed key in AL  (echo to screen)
; ============================================================
read_char PROC
    MOV  AH, 01h
    INT  21h
    LEA  DX, crlf
    CALL print_str
    RET
read_char ENDP

; ============================================================
;  UTILITY: read_decimal
;  Reads up to 3 decimal digits, returns value in BX
;  Returns 0FFFFh in BX on invalid input
; ============================================================
read_decimal PROC
    MOV  BX, 0
    MOV  CX, 0             ; digit count
rd_loop:
    MOV  AH, 01h
    INT  21h
    ; Enter key?
    CMP  AL, 0Dh
    JE   rd_done
    ; Backspace?
    CMP  AL, 08h
    JE   rd_done
    ; Digit?
    CMP  AL, '0'
    JL   rd_invalid
    CMP  AL, '9'
    JG   rd_invalid
    ; Accumulate
    SUB  AL, '0'
    MOVZX AX, AL
    MOV  DX, 10
    PUSH AX
    MOV  AX, BX
    MUL  DX                ; AX = BX * 10
    POP  DX
    ADD  AX, DX
    MOV  BX, AX
    INC  CX
    CMP  CX, 3
    JL   rd_loop
    ; Read rest until Enter
rd_flush:
    MOV  AH, 01h
    INT  21h
    CMP  AL, 0Dh
    JNE  rd_flush
    JMP  rd_done

rd_invalid:
    MOV  BX, 0FFFFh
rd_done:
    LEA  DX, crlf
    CALL print_str
    RET
read_decimal ENDP

; ============================================================
;  UTILITY: print_decimal
;  AX = unsigned 16-bit value to print
; ============================================================
print_decimal PROC
    MOV  CX, 0             ; digit count
    MOV  BX, 10
pd_push:
    MOV  DX, 0
    DIV  BX
    ADD  DL, '0'
    PUSH DX
    INC  CX
    CMP  AX, 0
    JNE  pd_push
pd_pop:
    POP  DX
    MOV  AH, 02h
    INT  21h
    LOOP pd_pop
    RET
print_decimal ENDP

END main
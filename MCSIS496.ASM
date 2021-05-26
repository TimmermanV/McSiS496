; Manual configuration tool for SiS 496/497
; Author: TimmermanV
 
config_addr equ 80002800h
addr_port equ 0cf8h
data_port equ 0cfch
sis496_id equ 04961039h

org 100h
cpu 486

main:
        mov dx, msg_title
        mov ah, 09h
        int 21h

        mov eax, config_addr    ; detect SiS496
        mov dx, addr_port
        out dx, eax
        mov dx, data_port
        in eax, dx
        cmp eax, sis496_id
        je .process_args

        mov dx, msg_no_sis496   ; show that SiS496 was not detected
        mov ah, 09h
        int 21h
        ; continue anyway

        .process_args:
        mov si, 81h             ; get arguments from Program Segment Prefix

        .process_options:
        call skip_spaces
        jz .help_and_exit
        cmp al, "-"
        jne .get_reg_size
        lodsw
        and ah, 1101_1111b      ; force uppercase
        mov bx, num_options*2
        .find_option:
        cmp ah, [options+bx-2]
        je .set_option
        sub bx, 2
        jnz .find_option
        jmp .invalid_args
        .set_option:
        mov byte [options+bx-1], 1
        jmp .process_options

        .help_and_exit:
        mov dx, msg_help
        mov al, 0               ; zero return code for success
        jmp .print_and_exit

        .get_reg_size:
        lodsb
        and al, 1101_1111b      ; force uppercase
        mov cl, 1               ; default reg size
        cmp al, "D"
        je .size_dword
        cmp al, "W"
        je .size_word
        cmp al, "B"
        je .size_byte
        jmp .invalid_args
        .size_dword:
        shl cl, 1
        .size_word:
        shl cl, 1
        .size_byte:
        mov [reg_size], cl      ; store register size in global
        
        .get_reg_nr:            ; dx = register number
        mov cx, 2
        xor dx, dx
        mov di, reg_nr_digits
        .process_nibble:
        lodsb
        cmp al, "0"
        jb .invalid_args        
        cmp al, "9" + 1
        jb .skip_uppercase
        and al, 1101_1111b      ; force uppercase, also clears cf
        .skip_uppercase:
        stosb                   ; copy input to reg_nr_digits so we can display it
        jb .digits_0_9          ; cf still indicates al <= "9"
        cmp al, "A"
        jb .invalid_args
        cmp al, "F"
        ja .invalid_args
        sub al, "A" - "9" - 1
        .digits_0_9:
        sub al, "0"
        shl dx, 4
        or dl, al
        loop .process_nibble

        ;.skip_optional_h:
        lodsb
        and al, 1101_1111b
        cmp al, "H"
        je .set_sis496_reg_nr
        dec si                  ; decrement si if it wasn't "H"

        .set_sis496_reg_nr:
        mov eax, config_addr
        mov al, dl
        and dl, 0000_0011b      ; lowest two bits for data_port
        or dx, data_port        ; dx = data port + two bit offset
        push dx
        and al, 1111_1100b      ; other bits for config_addr
        mov dx, addr_port
        out dx, eax             ; set config_addr
        pop word [reg_data_port]; store register data port in global
        call get_reg_value

        ;.show_msg_reg_nr:
        mov ax, cpt_msg_reg_nr - msg_reg_nr
        mul byte [opt_compact]
        add ax, msg_reg_nr
        mov dx, ax
        mov ah, 09h
        int 21h

        mov ebx, [reg_value]
        xor edi, edi            ; edi will remain 0 if no bit_set is specified
        .next_bit_set:
        call skip_spaces        
        jz .show_cur_and_set_val
        cmp al, "0"
        jb .show_cur_and_set_val
        cmp al, "9"
        ja .show_cur_and_set_val
        xor ah, ah
        xor cx, cx
        mov dx, [reg_size]
        shl dx, 3               ; register size from bytes to bits
        inc si
        jmp .process_dec_digit
        .load_dec_digit:
        lodsb
        cmp al, "="
        je .read_bin_digits
        cmp al, "0"
        jb .invalid_args
        cmp al, "9"
        ja .invalid_args
        .process_dec_digit:
        sub ax, "0"
        imul cx, 10
        add cx, ax              ; cx = bit index
        cmp cx, dx
        jae .invalid_args       ; bit index too high
        jmp .load_dec_digit

        .read_bin_digits:       ; first find the end, then process backwards
        push dx                 ; save reg size in bits
        mov dx, .read_bin_digit ; set dx to skip bin digits
        mov di, .fwd_end_of_bits
        ror ebx, cl             ; ensure that bits are inserted at the requested index

        .read_bin_digit:
        lodsb
        xor al, "0"             ; reduce to 1 bit (if "0" / "1")
        shr al, 1               ; shift bit into carry
        jnz .jmp_to_end
        jmp dx
        .jmp_to_end:
        jmp di

        .fwd_end_of_bits:
        mov dx, .process_bit
        mov di, .bwd_end_of_bits
        std                     ; start processing backwards
        dec si
        push si                 ; save si so we can continue afterwards
        dec si
        jmp .read_bin_digit

        .process_bit:
        rcr ebx, 1              ; replace bit by new value
        inc cl                  ; keep track of index so we can reverse in the end
        jmp .read_bin_digit

        .bwd_end_of_bits:
        cld                     ; restore direction forwards
        rol ebx, cl             ; restore original ebx rotation
        pop si                  ; restore si to continue processing args
        pop dx                  ; restore reg size in bits
        cmp cl, dl
        ja .invalid_args        ; too many bits written
        jmp .next_bit_set

        .show_cur_and_set_val:
        pushf                   ; remember why we stopped reading bit sets
        push ebx                ; remember the modified register value
        ;test byte [opt_compact], 1
        ;jnz .set_reg_value
        
        mov eax, "Cur "
        call show_reg_value     ; show current value
        pop dword [reg_value]   ; write modified value to [reg_value]
        ;test edi, edi
        ;jz .finished_one_reg
        mov eax, "Set "
        call show_reg_value     ; show set value

        .set_reg_value:
        call set_reg_value
        call get_reg_value

        mov eax, "New "
        call show_reg_value     ; show new value

        .finished_one_reg:
        popf                    ; restore why we stopped reading bit sets
        jz .success_exit        ; if it was the end of args, exit here
        jmp .get_reg_size       ; try reading another register size+number

        .success_exit:
        mov al, 0               ; zero return code for success
        jmp .exit

        .invalid_args:
        mov dx, msg_inval_args
        .fail_print_exit:
        mov al, 1               ; non-zero return code to indicate failure
        .print_and_exit:
        mov ah, 09h
        int 21h
        .exit:
        mov dx, end_of_line     ; make sure the last line has an end
        mov ah, 09h
        int 21h        
        mov ah, 4ch
        int 21h

; skip_spaces
; Skips spaces at register si. Returns at first `\r`. Otherwise skips all chars <= 20h.
; Returns first non-space char in al. SI is decremented so it points to this char.
; ZF is set when the end of line is reached.
; Requires at least 1 whitespace char, otherwise jumps to .invalid_args.
skip_spaces:
        cmp byte [si], 20h
        ja main.invalid_args
        .more_spaces:
        lodsb
        cmp al, `\r`
        je .done
        cmp al, 20h
        jbe .more_spaces
        .done:
        pushf
        dec si
        popf
        ret

; get_reg_value
; Sets [reg_value] to the value of a SiS496 register.
; Note: addr_port must be configured porior to calling this.
; Register size and data port are read from global vars.
get_reg_value:
        mov di, reg_value
        mov dx, [reg_data_port]
        cmp byte [reg_size], 2
        jb .size_byte
        je .size_word
        .size_dword:
        insd
        ret
        .size_word:
        insw
        ret
        .size_byte:
        insb
        ret

; set_reg_value
; Sets the value of a SiS496 register to [reg_value].
; Note: addr_port must be configured porior to calling this.
; Register size, value and data port are read from global vars.
set_reg_value:
        push si
        mov si, reg_value
        mov dx, [reg_data_port]
        cmp byte [reg_size], 2
        jb .size_byte
        je .size_word
        .size_dword:
        outsd
        pop si
        ret
        .size_word:
        outsw
        pop si
        ret
        .size_byte:
        outsb
        pop si
        ret

; show_reg_value
; Shows both the hexadecimal and binary representation of the value in ebx.
; The line is prefixed with a message header.
; args:
; eax - The first word (also literally) of the message header.
; ebx - The value to be shown as hex and bin digits
show_reg_value:
        push di
        mov di, reg_val_type
        stosd                   ; Store the word in the msg header

        mov di, buffer
        mov ebx, [reg_value]

        test byte [opt_bin_only], 1
        jnz .stos_bin

        ;.stos_hex:
        call stos_hex_digits
        mov al, "h"
        stosb
        test byte [opt_hex_only], 1
        jnz .print_msg
        mov ax, "  "
        stosw

        .stos_bin:
        call stos_bin_digits
        
        .print_msg:
        mov al, "$"
        stosb
        mov ax, cpt_msg_reg_val - msg_reg_val
        mul byte [opt_compact]
        add ax, msg_reg_val
        mov dx, ax
        mov ah, 09h
        int 21h

        pop di
        ret

; stos_hex_digits
; Stores a string of hexadecimal digits based on the value ebx.
; args:
; ebx - The value to be converted to hexadecimal digits
; di - destination for the digit string
stos_hex_digits:
        push ebx

        mov cx, [reg_size]
        shl cl, 3
        ror ebx, cl             ; ror bits that will be processed
        shr cl, 2               ; cl = nr of hexdec digits

        .get_next_digit:
        rol ebx, 4
        mov al, bl
        and al, 0Fh
        add al, "0"
        cmp al, "9"
        jbe .store_digit
        add al, "A" - "9" - 1

        .store_digit:
        stosb
        loop .get_next_digit
        pop ebx
        ret

; stos_bin_digits
; Stores a string of binary digits based on the value ebx.
; args:
; ebx - The value to be converted to binary digits
; di - destination for the digit string
stos_bin_digits:
        push ebx
        
        mov cx, [reg_size]
        shl cl, 3
        ror ebx, cl             ; ror bits that will be processed

        jmp .next_digit

        .add_byte_sep:
        mov al, cl
        and al, 7
        jnz .add_nibble_sep
        mov al, " "
        stosb
        jmp .next_digit

        .add_nibble_sep:
        mov al, cl
        and al, 3
        jnz .next_digit
        mov al, "_"
        stosb

        .next_digit:
        xor al, al
        rol ebx, 1
        adc al, "0"
        stosb
        loop .add_byte_sep
        pop ebx        
        ret

; options
num_options     equ 3
options:        db "B"
opt_bin_only:   db 0
                db "H"
opt_hex_only:   db 0
                db "C"
opt_compact:    db 0

; globals
reg_size:       dw 0    ; size of the current register in bytes (1/2/4) as word
reg_data_port:  dw 0    ; data_port offset with the lowest two bits of the register nr
reg_value:      dd 0    ; current value of the register

; messages
msg_title:      db "Manual configuration tool for SiS 496/497 v1.01", "$"
msg_no_sis496:  db `\r\n`, "Failed to detect SiS 496/497!", "$"
msg_inval_args: db `\r\n`, "Invalid arguments!" ; continued below
msg_help:       db `\r\n\r\n`, "Usage:", `\r\n`
                db "mcsis496 [option]... register [bit_changes...] [register [bit_changes...]]...", `\r\n`
                db "option = -b show binary representation only", `\r\n`
                db "         -h show hexadecimal representation only", `\r\n`
                db "         -c compact output, shows final value only", `\r\n`
                db "register = size 'b'/'w'/'d' (for 8/16/32-bit) + hexdec regnr [+ 'h']", `\r\n`
                db "bit_changes = index of lowest bit (decimal) + '=' + binary digits", `\r\n\r\n`
                db "Examples:", `\r\n`
                db "mcsis496 -h d00h", `\r\n`
                db "mcsis496 b40h 0=10 5=1 6=1", `\r\n`
                db "mcsis496 -c -b b40h 2=010 b81h 2=010", "$"
end_of_line:    db `\r\n`, "$"
msg_reg_nr:     db `\r\n`               ; continued below
cpt_msg_reg_nr: db `\r\n`, "Register "  ; continued below
reg_nr_digits:  db "FFh", "$"
msg_reg_val:    db `\r\n`               ; continued below
reg_val_type:   db "Cur value"          ; continued below
cpt_msg_reg_val:db ": "                 ; continued below
buffer:

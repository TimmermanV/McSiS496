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

        lodsb
        and al, 1101_1111b      ; force uppercase
        mov bx, num_options*2
        .find_option:
        cmp al, [options+bx-2]
        je .set_option
        sub bx, 2
        jnz .find_option
        jmp .invalid_args
        .set_option:
        mov byte [options+bx-1], 1
        mov al, [si]            ; peek for space
        cmp al, 20h
        jbe .process_options    ; try reading another option
        jmp .invalid_args

        .help_and_exit:
        mov dx, msg_help
        mov al, 0               ; zero return code for success
        jmp .print_and_exit

        .get_reg_size:          ; reg size is put into cx
        and al, 1101_1111b      ; force uppercase
        mov cx, 1               ; default reg size
        cmp al, "D"
        je .size_dword
        cmp al, "W"
        je .size_word
        cmp al, "B"
        je .size_byte
        jmp .invalid_args
        .size_dword:
        shl cx, 1
        .size_word:
        shl cx, 1
        .size_byte:
        
        .get_reg_nr:            ; reg nr is put into dx
        push cx
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
        pop cx                  ; restore cx to contain reg size

        ;.skip_optional_h:
        mov al, [si]            ; peek for value "H"
        and al, 1101_1111b
        cmp al, "H"
        jne .set_sis496_reg_nr
        inc si

        .set_sis496_reg_nr:
        push dx
        mov eax, config_addr
        mov al, dl
        and al, 1111_1100b
        mov dx, addr_port
        out dx, eax
        pop dx

        call get_reg_value
        mov ebx, eax

        ;.show_msg_reg_nr:
        push dx
        mov ax, cpt_msg_reg_nr - msg_reg_nr
        mul byte [opt_compact]
        add ax, msg_reg_nr
        mov dx, ax
        mov ah, 09h
        int 21h
        pop dx

        test byte [opt_compact], 1
        jnz .process_bit_sets
        call show_reg_value

        .process_bit_sets:
        call skip_spaces        
        jz .success_exit        ; end of arguments: jump to exit
        cmp al, "0"
        jb .invalid_args        ; < "0" is invalid at this point
        cmp al, "9"
        ja .get_reg_size        ; > "9" could mean another register

        push dx
        .next_bit_set:
        push cx                 ; save register size in bytes
        xor ch, ch              ; use ch for the bit index
        jmp .process_dec_digit  ; first digit is already loaded by skip_spaces
        .load_dec_digit:
        lodsb
        .process_dec_digit:
        cmp al, "="
        je .check_bit_index
        cmp al, "0"
        jb .invalid_args
        cmp al, "9"
        ja .invalid_args
        sub al, "0"
        mov dl, ch              ; dl = ch
        shl ch, 3               ; ch = ch * 8 + dl * 2
        shl dl, 1
        add ch, dl
        add ch, al              ; ch = bit index
        cmp ch, 31              ; max index in any case is 31
        ja .invalid_args
        jmp .load_dec_digit

        .check_bit_index:       ; check if index is out of range
        shl cl, 3               ; register size from bytes to bits
        cmp ch, cl
        jae .invalid_args       ; bit index >= nr bits

        sub cl, ch              ; cl = max nr of bin digits

        cmp [si], byte 20h      ; must specify at least 1 bit
        jbe .invalid_args

        xor ah, ah              ; count bin digits in ah
        xor edi, edi            ; use edi for the bit mask
        xor edx, edx            ; use edx for the bit pattern
        .next_bin_digit:
        mov al, [si]
        cmp al, 20h
        jbe .apply_bit_set
        cmp al, "0"
        jb .invalid_args
        cmp al, "1"
        ja .invalid_args
        sub al, "0"
        shl edi, 1
        inc edi
        shl edx, 1
        or dl, al
        inc ah
        cmp ah, cl
        ja .invalid_args        ; too many digits
        inc si
        jmp .next_bin_digit

        .apply_bit_set:
        mov cl, ch
        shl edi, cl
        shl edx, cl
        not edi
        and ebx, edi
        or ebx, edx

        call skip_spaces
        jz .set_new_reg_value
        cmp al, "9"
        ja .set_new_reg_value   ; > "9" could mean another register
        pop cx                  ; restore register size in bytes
        jmp .next_bit_set

        .set_new_reg_value:
        pop cx                  ; restore register size in bytes
        pop dx                  ; restore register number
        push ax                 ; remember the last read char
        pushf                   ; remember why we stopped reading bit sets

        test byte [opt_compact], 1
        jnz .set_reg_value
        mov [reg_val_type], dword "Set "
        call show_reg_value

        .set_reg_value:
        mov eax, ebx
        call set_reg_value
        call get_reg_value
        mov ebx, eax

        mov [reg_val_type], dword "New "
        call show_reg_value

        popf                    ; restore why we stopped reading bit sets
        jz .success_exit        ; if it was the end of args, exit here
        mov [reg_val_type], dword "Cur "
        pop ax                  ; restore the last read char
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
; Returns last read char in al. ZF is set when the end of line is reached.
skip_spaces:
        lodsb
        cmp al, `\r`
        je .done
        cmp al, 20h
        jbe skip_spaces
        .done:
        ret

; get_reg_value
; Returns the value of a SiS496 register in eax/ax/al.
; Note: addr_port must be configured porior to calling this.
; args:
; cl - The size of the register in bytes.
; dx - The register number.
get_reg_value:
        push dx
        and dl, 0000_0011b
        or dx, data_port
        cmp cl, 2
        jb .size_byte
        je .size_word
        .size_dword:
        in eax, dx
        jmp .done
        .size_word:
        in ax, dx
        jmp .done
        .size_byte:
        in al, dx
        .done:
        pop dx
        ret

; set_reg_value
; Sets the value of a SiS496 register to eax.
; Note: addr_port must be configured porior to calling this.
; args:
; eax/ax/al - The value to set on the register.
; cl - The size of the register in bytes.
; dx - The register number.
set_reg_value:
        push dx
        and dl, 0000_0011b
        or dx, data_port
        cmp cl, 2
        jb .size_byte
        je .size_word
        .size_dword:
        out dx, eax
        jmp .done
        .size_word:
        out dx, ax
        jmp .done
        .size_byte:
        out dx, al
        .done:
        pop dx
        ret

; show_reg_value
; Shows both the hexadecimal and binary representation of the value in ebx.
; The line is prefixed with a message header.
; args:
; ebx - The value to be shown as hex and bin digits
; cx - The number of bytes to process (4=ebx,2=bx,1=bl)
show_reg_value:
        push dx
        mov di, buffer

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
        pop dx
        ret

; stos_hex_digits
; Stores a string of hexadecimal digits based on the value ebx.
; args:
; ebx - The value to be converted to hexadecimal digits
; cx - The number of bytes to process (4=ebx,2=bx,1=bl)
; di - destination for the digit string
stos_hex_digits:
        push ebx
        push cx

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
        pop cx
        pop ebx
        ret

; stos_bin_digits
; Stores a string of binary digits based on the value ebx.
; args:
; ebx - The value to be converted to binary digits
; cx - The number of bytes to process (4=ebx,2=bx,1=bl)
; di - destination for the digit string
stos_bin_digits:
        push ebx
        push cx

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
        pop cx
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

; messages
msg_title:      db "Manual configuration tool for SiS 496/497 v1.01", "$"
msg_no_sis496:  db `\r\n`, "Failed to detect SiS 496/497!", "$"
msg_inval_args: db `\r\n`, "Invalid arguments!" ; continued below
msg_help:       db `\r\n\r\n`, "Usage:", `\r\n`
                db "mcsis496 register [bit_changes...] [register [bit_changes...]]...", `\r\n`
                db "register = size 'b'/'w'/'d' (for 8/16/32-bit) + hexdec regnr [+ 'h']", `\r\n`
                db "bit_changes = index of lowest bit (decimal) + '=' + binary digits", `\r\n\r\n`
                db "Examples:", `\r\n`
                db "mcsis496 d00h", `\r\n`
                db "mcsis496 b40h 0=10 5=1 6=1", `\r\n`
                db "mcsis496 b40h 2=010 b81h 2=010", "$"
end_of_line:    db `\r\n`, "$"
msg_reg_nr:     db `\r\n`               ; continued below
cpt_msg_reg_nr: db `\r\n`, "Register "  ; continued below
reg_nr_digits:  db "FFh", "$"
msg_reg_val:    db `\r\n`               ; continued below
reg_val_type:   db "Cur value"          ; continued below
cpt_msg_reg_val:db ": "                 ; continued below
buffer:

; Manual configuration tool for SiS 496/497
; Author: TimmermanV
 
config_addr equ 80002800h
addr_port equ 0cf8h
data_port equ 0cfch
sis496_id equ 04961039h

org 100h

main:
        mov dx, msg_title
        mov ah, 09h
        int 21h

        mov eax, config_addr    ; detect SiS496
        mov dx, addr_port
        out dx, eax
        mov cx, 4               ; read dword
        call get_reg_value
        cmp eax, sis496_id
        je .process_args

        mov dx, msg_no_sis496
        mov ah, 09h
        int 21h
        ; continue anyway

        .process_args:
        mov si, 81h             ; get aruments from Program Segment Prefix

        call skip_spaces
        jnz .get_reg_size
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
        mov eax, config_addr
        mov al, dl
        mov dx, addr_port
        out dx, eax

        call get_reg_value
        mov ebx, eax

        ;.show_msg_reg_nr:
        mov dx, msg_reg_nr
        mov ah, 09h
        int 21h

        call show_reg_value
        call skip_spaces
        jz .success_exit        ; when not writing any bits, exit here

        .next_bit_set:
        push cx                 ;
        cmp al, "="             ; don't allow skipping the bit index
        je .invalid_args
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
        cmp ch, 31              ; max index in any case is 32
        ja .invalid_args
        jmp .load_dec_digit

        .check_bit_index:       ; check if index is out of range
        shl cl, 3               ; bytes to bits
        cmp ch, cl
        jae .invalid_args       ; bit index >= nr bits

        sub cl, ch              ; cl = max nr of bin digits

        cmp [si], byte 20h      ; must specify at least 1 bit
        jbe .invalid_args

        xor ah, ah              ; count bin digits in ah
        xor edi, edi            ; use edi for the bit mask
        xor edx, edx            ; use edx for the bit pattern
        .next_bin_digit:
        lodsb
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
        jmp .next_bin_digit

        .apply_bit_set:
        mov cl, ch
        shl edi, cl
        shl edx, cl
        not edi
        and ebx, edi
        or ebx, edx

        dec si
        call skip_spaces
        jz .set_new_reg_value
        pop cx
        jmp .next_bit_set

        .set_new_reg_value:
        pop cx

        mov [msg_reg_val], dword "Set "
        call show_reg_value
        mov eax, ebx
        call set_reg_value
        call get_reg_value
        mov ebx, eax

        mov [msg_reg_val], dword "New "
        call show_reg_value

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
; returns the value of the current SiS496 register in eax
; args:
; cl - The size of the register in bytes.
get_reg_value:
        mov dx, data_port
        cmp cl, 2
        jb .size_byte
        je .size_word
        .size_dword:
        in eax, dx
        ret
        .size_word:
        in ax, dx
        ret
        .size_byte:
        in al, dx
        ret

; set_reg_value
; sets the value of the current SiS496 register to eax
; args:
; cl - The size of the register in bytes.
set_reg_value:
        mov dx, data_port
        cmp cl, 2
        jb .size_byte
        je .size_word
        .size_dword:
        out dx, eax
        ret
        .size_word:
        out dx, ax
        ret
        .size_byte:
        out dx, al
        ret

; show_reg_value
; Shows both the hexadecimal and binary representation of the value in ebx.
; The line is prefixed with a message header.
; args:
; ebx - The value to be shown as hex and bin digits
; cx - The number of bytes to process (4=ebx,2=bx,1=bl)
show_reg_value:
        mov di, buffer
        call stos_hex_digits
        mov al, "h"
        stosb
        mov ax, "  "
        stosw
        call stos_bin_digits
        mov ax, `\r\n`
        stosw
        mov al, "$"
        stosb
        mov dx, msg_reg_val
        mov ah, 09h
        int 21h
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

msg_title:      db "Manual configuration tool for SiS 496/497 v1.0", 13, 10, "$"
msg_no_sis496:  db "Failed to detect SiS 496/497!", 13, 10, "$"
msg_inval_args: db "Invalid arguments!", 13, 10 ; No $
msg_help:       db "Usage: mcsis496 b40h 0=10", 13, 10, "$"
msg_reg_nr:     db "Register " ; No $
reg_nr_digits:  db "FFh", 13, 10, "$"
msg_reg_val:    db "Cur value: " ; No $
buffer:

# McSiS496
McSiS496 is a simple command line tool for DOS that allows manual configuration of bits in configuration registers in the PCI configuration of the SiS85C496/497.
I will show the current contents of the requested register and will attempt to modify any requested bits. To know which bits do what, track down a copy of the technical reference / specification "SiS 85C496/497 Preliminary Rev 3.0 July 1995", and read part IV chapter 3 "PCI Configuration Space Registers".

Usage:
```
mcsis496 register [bit_changes...] [register [bit_changes...]]...
register = size 'b'/'w'/'d' (for 8/16/32-bit) + hexdec regnr [+ 'h']
bit_changes = index of lowest bit (decimal) + '=' + binary digits
```

Examples:
```
mcsis496 d00h
mcsis496 b40h 0=10
mcsis496 b40h 2=010 b81h 2=010
```

If you don't specify any bit changes, the program will just show the current value of the register. If you do specify any bit changes, the program will read and display the current value, apply your requested changes, show the result and write the new value to the register. Finally it will read and display the (new) value of the register.

Example output:
```
C:\>mcsis496 dc8 12=1010 8=1110
Manual configuration tool for SiS 496/497 v1.01

Register C8h
Cur value: 00FF0000h  0000_0000 1111_1111 0000_0000 0000_0000
Set value: 00FFAE00h  0000_0000 1111_1111 1010_1110 0000_0000
New value: 00FFAE00h  0000_0000 1111_1111 1010_1110 0000_0000
```

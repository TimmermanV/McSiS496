# McSiS496
McSiS496 is a simple command line tool for DOS that allows manual configuration of bits in SiS496 registers.
I will show the current contents of the requested register and will attempt to modify any requested bits.

Usage:
```
mcsis496.com register [bit changes]

register: (b40, w02h, DC8H) (b|w|d)[0-9A-F]{2}h?
  size (b for byte/8-bit, w for word/16-bit, d for double word 32-bit)
  followed by 2 hexadecimal digits for the register number
  followed by an optional h
  
[bit changes]: (2=010, 25=0, 0=00000101) [0-9]+=[01]+)
  bit index for the least significant bit (decimal)
  followed by equal sign
  followed by a sequence of binary digits
```

Example output:
```
C:\>mcsis496 dc8 12=1010 8=1110
Manual configuration tool for SiS 496/497 v1.0
Register C8h
Cur value: 00FF0000h  0000_0000 1111_1111 0000_0000 0000_0000
Set value: 00FAE000h  0000_0000 1111_1010 1110_0000 0000_0000
New value: 00FAE000h  0000_0000 1111_1010 1110_0000 0000_0000
```

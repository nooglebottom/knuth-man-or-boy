;For ml64, Windows x86-64
;ml64 <filename>.asm /Cp /link /ENTRY:ENTRY /SUBSYSTEM:CONSOLE kernel32.lib user32.lib /STACK:<stacksize>
;Got up to 27 with a /STACK:10737418240 (10GB). 

COMMENT ~
Some hideous ALGOL60 by Knuth:

begin
real procedure A(k, x1, x2, x3, x4, x5);
value k; integer k;
begin
real procedure B;
begin
k := k - 1;
B := A := A(k, B, x1, x2, x3, x4)
end;
if k <= 0 then A : = x4 + x5 else B
end
outreal(A(10, 1, -1, -1, 1, 0))
end

Algol uses "pass by name", so there's a little bit of nastiness to be had here. I'm not actually 
sure what the second B in B := refers to.

After some thinking, it looks like it refers to B in the frame when it was put in there.
Which is a little annoying.

So...I'll pass structures containing pointers to functions that take that structure -_-'.
struct S{
	int (*fun)(S*);
	...
};
Then things should be sensible again.
~

COMMENT +
I just thought of a way to make this use less stack.
The structure needs only be 32 bits.
I only have 16GB of memory, which needs 34 bits to address, so that the stack should be addressable by a 34-bit offset.
So keeping a stack base pointer somewhere, I can shrink the pointer.
The stack's elements are all 8-byte aligned, so that 3 bits (or 4 if I keep the frame pointer 16 byte aligned...) are 
always zero. That means 31 (or 30) bits for a pointer, and since there are only 4 functions to be called, this should be 
completely doable.

In the end I went for a 35-bit pointer, since the bit I want is 16-byte aligned, which allows a potential 32GB.

That got to 28 with 14GB of stack.

currently A and B both do 48 bytes of stacking
calls might mess up the exception mechanism, but they could probably be simulated...
B then needs to allocate 40 to call A, but A could need NOTHING to call B.
A frame pointer would be needed.
+

_TEXT SEGMENT

;A's new Stack plan
;free	r9		72	-use for A
;(x5:x4) r8		64
;(x3:x2) rdx	56
;(x1:k) rcx		48
;return			40 ;allocate 40
;'B'			32
;call space		24
;call space		16
;call space		8
;call space		0
A PROC PUBLIC FRAME
	sub rsp,40
	.ALLOCSTACK 40
	.ENDPROLOG
	mov [rsp+64],r8
	cmp ecx,0	;check k	...I don't know if cmp zeroes rcx? weeeeird
	jle sum
	;On this branch the shadow space needs populating.
	mov [rsp+48],rcx
	mov [rsp+56],rdx
	;now I need to make B's 'pointer'
	mov rcx,[stack_base]
	sub rcx,rsp		;'B' is 16 byte aligned, so I can go for 31+4 bits of pointer, for 35. so it has 4 dead bits, 31 alive bits
	shr rcx,3
	mov [rsp+32],ecx
	call B				;call B on that
	mov eax,[rsp+72]	;get the return value out
	jmp done
sum:
	mov rcx,r8
	call GETSUM
done:
	add rsp,40
	ret
A ENDP

GETSUM PROC PRIVATE FRAME
	sub rsp,40
	.ALLOCSTACK 40
	.ENDPROLOG
	mov [rsp+48],rcx
test1:cmp ecx,1
	jne test2
	call f0
	jmp next_tests
test2:cmp ecx,3
	jne test3
	call f1
	jmp next_tests
test3:cmp ecx,5
	jne call_B_1
	call fm1
	jmp next_tests
call_B_1:
	mov ecx,ecx
	call B
next_tests:
	mov [rsp+56],eax
	
	mov ecx,[rsp+52]
test4:cmp ecx,1
	jne test5
	call f0
	jmp end_tests
test5:cmp ecx,3
	jne test6
	call f1
	jmp end_tests
test6:cmp ecx,5
	jne call_B_2
	call fm1
	jmp end_tests
call_B_2:
	call B
end_tests:
	add eax,[rsp+56]
	add rsp,40
	ret
GETSUM ENDP

;B's stack plan
;free			72
;free			64
;free			56
;('pointer')rcx	48
;return			40
;rbx			32
;(p5)			24
;(p4:p3)		16
;(p2:p1)		8
;(p1:p0)		0
B PROC PUBLIC FRAME
	push rbx
	.PUSHREG rbx
	sub rsp,32
	.ALLOCSTACK 32
	.ENDPROLOG
	
	;need to extract the frame poitner
	mov eax,ecx
	mov rbx,[stack_base]
	shl rax,3
	sub rbx,rax
	
	dec DWORD PTR [rbx + 48];k <- k-1 in that frame

	mov r8,[rbx+60]			;x4:x3
	mov rdx,[rbx+52]		;x2:x1
	;rcx contains B in ecx
	shl rcx,32
	mov eax,[rbx+48]
	or rcx,rax
	call A					;A(k,B,x1,x2,x3,x4)
	mov [rbx+72],eax		;save the result (as in the original code)

	add rsp,32
	pop rbx
	ret
B ENDP
_TEXT ENDS

;Business to actually do things.
EXTERN __imp_ExitProcess:PROC
EXTERN __imp_GetStdHandle:PROC
EXTERN __imp_WriteFile:PROC
EXTERN __imp_wsprintfA:PROC 

CONST SEGMENT
ALIGN 16
;initial arguments
arg1	dq	0300000000h;f1:??
arg2	dq	0500000005h;fm1:fm1
arg3	dq	0100000003h;f0:f1

format_string	db	"%d -> %d",0dh,0ah,0
len_format_string = $-format_string
end_string 		db	"Stack overflow!"
len_end_string = $ - end_string
CONST ENDS

_BSS SEGMENT
ALIGN 16
stack_base		dq	?
output_string	db	1024 dup (?)
_BSS ENDS

_TEXT SEGMENT

f0:		xor eax,eax
		ret
f1:		mov eax,1
		ret
fm1:	mov eax,-1
		ret

EXTERN __imp_RtlUnwind:PROC
EHANDLER PROC PRIVATE FRAME
		sub rsp,40
		.ALLOCSTACK 40
		.ENDPROLOG
		
		;check what we can do with the exception
		cmp DWORD PTR [rcx+4],0
		jne do_nothing	;it's not something I can deal with unless it's continuable.		
		cmp DWORD PTR [rcx],0c00000fdh 	;check for a stack overflow
		jne do_nothing ;I can't do anything with it
		
		;so...a stack overflow is to be had!
		;It could come from windows, but that would be crazy.
		
		mov r10,rdx	;save the exception frame
		mov r9,0
		mov r8,rcx
		lea rdx,[ehandler_safe_position]
		mov rcx,r10
		call QWORD PTR [__imp_RtlUnwind]
		
		xor rax,rax
		add rsp,40
		ret
		
do_nothing:
		mov rax,1
		add rsp,40
		ret
EHANDLER ENDP 

ENTRY PROC PUBLIC FRAME:EHANDLER
		sub rsp,56
		.ALLOCSTACK 56
		.ENDPROLOG
		
		mov [stack_base],rsp
		
		mov rcx,-11
		call QWORD PTR [__imp_GetStdHandle]
		mov [rsp+80],rax
		
		mov QWORD PTR [rsp+88],0
next:
		;let's make...everything I need -_-'
		mov r8,[arg3]
		mov rdx,[arg2]
		mov rcx,[arg1]
		or rcx,[rsp+88]
		call A
		
		mov r9,rax
		mov r8,[rsp+88]
		lea rdx,[format_string]
		lea rcx,[output_string]
		call QWORD PTR [__imp_wsprintfA]
				
		mov QWORD PTR [rsp+32],0
		lea r9,[rsp+64]
		mov r8,rax
		lea rdx,[output_string]
		mov rcx,[rsp+80]
		call QWORD PTR [__imp_WriteFile]

		inc QWORD PTR [rsp+88]
		jmp next
		
ehandler_safe_position::	
		mov QWORD PTR [rsp+32],0
		lea r9,[rsp+64]
		mov r8,len_end_string
		lea rdx,[end_string]
		mov rcx,[rsp+80]
		call QWORD PTR [__imp_WriteFile]
	
		xor rcx,rcx
		call QWORD PTR [__imp_ExitProcess]
		
		add rsp,40
		ret
ENTRY ENDP
_TEXT ENDS
END

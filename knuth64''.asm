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

That got to 28 with 14GB of stack.

currently A and B both do 48 bytes of stacking
calls might mess up the exception mechanism, but they could probably be simulated...
B then needs to allocate 40 to call A, but A could need NOTHING to call B.
A frame pointer would be needed.

29 now.
A: 32 needed
B: 8 needed.
+

_TEXT SEGMENT

;so...weirdly CALLS SEEM TO WORK INSIDE PROCEDURES???? and still unwind fine. WELP.
pretend_call MACRO target:req
LOCAL post
	call target
;	lea rdx,post
;	push rdx
;	jmp target
;post:
ENDM

pretend_return MACRO
	ret
;	pop rdx
;	jmp rdx
ENDM

;AandB container procedure
;free		;40
;(arg3)r8	;32
;(arg2)rdx	;24
;(arg1)rcx	;16
;return		;8
;rbp		;0	<-frame pointer.
AandB PROC PUBLIC FRAME
	push rbp
	.PUSHREG rbp
	mov rbp,rsp
	.SETFRAME rbp,0
	.ENDPROLOG
	
	;push my arguments
	push r8		;24
	push rdx	;16
	push rcx	;8
	;simulate a call!
	pretend_call A
	mov rsp,rbp
	pop rbp
	ret
	
;A's stack:
;(x5:x4)24
;(x3:x2)16
;(x1:k)	8
;return	0
A:	cmp DWORD PTR [rsp+8],0
	jle sum
	mov rcx,[stack_base]
	sub rcx,rsp
	shr rcx,3
	jmp B	;B's kind of a tail here...
sum:;do the sum.
	cmp DWORD PTR [rsp+24],1
	jne sum_2
	mov rax,0
	jmp sum_next
sum_2:cmp DWORD PTR [rsp+24],3
	jne sum_3
	mov rax,1
	jmp sum_next
sum_3:cmp DWORD PTR [rsp+24],5
	jne sum_4
	mov rax,-1
	jmp sum_next
sum_4:mov ecx,[rsp+24]
	pretend_call B
sum_next:
	push rax
	cmp DWORD PTR [rsp+36],1
	jne sum_5
	add DWORD PTR [rsp],0
	jmp sum_end
sum_5:cmp DWORD PTR [rsp+36],3
	jne sum_6
	add DWORD PTR [rsp],1
	jmp sum_end
sum_6:cmp DWORD PTR [rsp+36],5
	jne sum_7
	add DWORD PTR [rsp],-1
	jmp sum_end
sum_7:mov ecx,[rsp+36]
	pretend_call B
	add [rsp],eax
sum_end:
	pop rax
	pretend_return

B:	mov eax,ecx
	mov rdx,[stack_base]
	shl rax,3
	sub rdx,rax
	
	dec DWORD PTR [rdx+8]
	
	push QWORD PTR [rdx+20]
	push QWORD PTR [rdx+12]
	shl rcx,32
	mov eax,DWORD PTR [rdx+8]
	or rcx,rax
	push rcx
	pretend_call A
	add rsp,24
	pretend_return
AandB ENDP

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
		call AandB
		
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

;For ml64, Windows x86-64
;ml64 knuth64.asm ehandler.asm /Cp /link /ENTRY:ENTRY /SUBSYSTEM:CONSOLE kernel32.lib user32.lib /STACK:<stacksize>
;Got up to 27 with a /STACK:10737418240 (10GB). 

COMMENT ~ (OLD NOTES)
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

_TEXT SEGMENT

;int32_t A(int32_t, void *, void *, void *, void *, void *); 
;void* parameter: some POD with a pointer to an int32_t function taking a pointer to that POD as parameter.
;A's Stack plan
;x5				104
;x4				96
;(x3) r9		88
;(x2) r8		80
;(x1) rdx		72
;(k) rcx		64 
;return			56 ;allocate 56
;A				48
;frame for B	40
;pointer for B	32
;call space		24
;call space		16
;call space		8
;call space		0
A PROC PUBLIC FRAME
	sub rsp,56
	.ALLOCSTACK 56
	.ENDPROLOG
	cmp ecx,0	;check k
	jle sum
	;On this branch the shadow space needs populating.
	mov [rsp+64],rcx
	mov [rsp+72],rdx
	mov [rsp+80],r8
	mov [rsp+88],r9
	mov [rsp+40],rsp	;save the frame pointer for B
	lea rax,B
	mov [rsp+32],rax	;save B's address for B
	lea rcx,[rsp+32]
	call B				;call B on that pointer
	mov eax,[rsp+48]	;get the return value out
	jmp done
sum:
	mov rcx,[rsp+96]	
	call QWORD PTR [rcx];call x4
	mov [rsp+48],eax	;save return
	mov rcx,[rsp+104]	
	call QWORD PTR [rcx];call x5
	add eax,[rsp+48]	;sum to return.
done:
	add rsp,56
	ret
A ENDP

;B's stack plan
;free			88
;free			80
;free			72
;(pointer)rcx	64
;return			56
;rbx			48 ;allocate 48
;p5				40
;p4				32
;p3				24
;p2				16
;p1				8
;p0				0
B PROC PUBLIC FRAME
	push rbx
	.PUSHREG rbx
	sub rsp,48
	.ALLOCSTACK 48
	.ENDPROLOG

	mov rbx,[rcx+8]			;get the saved frame pointer for A
	dec DWORD PTR [rbx + 64];k <- k-1 in that frame

	movdqu xmm0,[rbx+88]
	movdqa [rsp+32],xmm0	;x3 and x4.
	mov r9,[rbx+80]			;x2
	mov r8,[rbx+72]			;x1
	mov rdx,rcx				;B
	mov rcx,[rbx+64]		;k
	call A					;A(k,B,x1,x2,x3,x4)
	mov [rbx+48],eax		;save the result (as in the original code)

	add rsp,48
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
;The three 'functions' needed by the operation.
ALIGN 16
pf0		dq f0
pf1		dq f1
pfm1	dq fm1

;Output nonsense.
format_string	db	"%d -> %d",0dh,0ah,0
len_format_string = $-format_string
end_string 		db	"Stack overflow!"
len_end_string = $ - end_string
CONST ENDS

;Static buffer for formatting the string since I'm lazy and there's only one thread, thanks.
_BSS SEGMENT
output_string	db	1024 dup (?)
_BSS ENDS

_TEXT SEGMENT

;Function definitions. They're all leaves.
f0:		xor eax,eax
		ret
f1:		mov eax,1
		ret
fm1:	mov eax,-1
		ret
		
;Exception handler stuff moved to ehandler.asm
EXTERN EHANDLER:PROC
PUBLIC ehandler_safe_position

;Finally, the program entry point.
ENTRY PROC PUBLIC FRAME:EHANDLER
		sub rsp,56
		.ALLOCSTACK 56
		.ENDPROLOG
		
		;Get and save STANDARD_OUTPUT_HANDLE
		mov rcx,-11
		call QWORD PTR [__imp_GetStdHandle]
		mov [rsp+80],rax
		
		mov QWORD PTR [rsp+88],0	;[rsp+88] will iterate over k, starting from 0.
next:
		lea r11,[pf0]
		mov [rsp+40],r11			;0
		lea r10,[pf1]
		mov [rsp+32],r10			;1
		lea r9,[pfm1]				;-1
		lea r8,[pfm1]				;-1
		lea rdx,[pf1]				;1
		mov rcx,[rsp+88]			;here's k!
		call A
		
		;Format the output.
		mov r9,rax
		mov r8,[rsp+88]
		lea rdx,[format_string]
		lea rcx,[output_string]
		call QWORD PTR [__imp_wsprintfA]
		;Print the formatted string.
		mov QWORD PTR [rsp+32],0
		lea r9,[rsp+64]
		mov r8,rax
		lea rdx,[output_string]
		mov rcx,[rsp+80]
		call QWORD PTR [__imp_WriteFile]

		;increase k
		inc QWORD PTR [rsp+88]
		jmp next	;Loop 'forever' ;) Actually just until the stack overflow exception comes.
		
ehandler_safe_position::	;Two colons means a nonlocal label, visible beyond PROC scope.
		mov QWORD PTR [rsp+32],0
		lea r9,[rsp+64]
		mov r8,len_end_string
		lea rdx,[end_string]
		mov rcx,[rsp+80]
		call QWORD PTR [__imp_WriteFile]
	
		xor rcx,rcx
		call QWORD PTR [__imp_ExitProcess]
ENTRY ENDP
_TEXT ENDS
END

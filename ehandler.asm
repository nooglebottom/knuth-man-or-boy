;As it doesn't change over various implementations, the exception handler is out here in another file.
;It's probably not terribly enlightening.
;Also PROC FRAME:bleh seems to be VERY bad at scope.

;An exception handler to catch the inevitable stack overflow.
;I'm not going to expound on too many details here.
EXTERN __imp_RtlUnwind:PROC
EXTERN ehandler_safe_position:PROC	;PROC or DWORD...hm.

_TEXT SEGMENT
EHANDLER PROC PUBLIC FRAME
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
		
		;The parameters need to be shuffled around a bit for RtlUnwind
		xor r9,r9
		mov r8,rcx
		mov rcx,rdx
		lea rdx,[ehandler_safe_position]
		call QWORD PTR [__imp_RtlUnwind]
		
		;I don't think RtlUnwind actually returns (here),
		;since that hardly makes sense,
		;but I'm not 100% certain so there's some safety epilogue here.
		xor rax,rax
		add rsp,40
		ret
		
do_nothing:
		mov rax,1
		add rsp,40
		ret
EHANDLER ENDP 
_TEXT ENDS
END

.intel_syntax noprefix

.rodata
.p2align 4
# splat helper
splat: .zero 16
# constant for get_partial_unsafe indices
indices: .byte 0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15
# keys
key1: .long 0xF2784542, 0xB09D3E21, 0x89C222E5, 0xFC3BC28E
key2: .long 0x03FCE279, 0xCB6B2E9B, 0xB361DC58, 0x39132BD9
key3: .long 0xD0012E32, 0x689D2B7D, 0x5544B1B7, 0xC78B122B

.text
.global compress_all
.type compress_all, @function

# compress all bytes at address rdi with length rsi into a 128-bit vector
compress_all:
  # some hot paths
  mov rax, rsi
  test rax, rax
  je ret0
  cmp rax, 16
  jb get_partial
  ja over_16
  
  # fast path for len == 16
  
  movdqu xmm0, [rdi]
  # splat len into xmm1
  movd xmm1, esi
  pshufb xmm1, xmm2
  # add len
  paddb xmm0, xmm1
  ret
over_16:
  # store initial address
  push rbx
  mov rbx, rdi
  # load initial hash vector (xmm0)
  and rax, 0xf
  je extra0
  
  # extra bytes was not 0 (get partial unsafe)
  # keep in sync with below implementation!
  
  # splat len
  movd xmm1, rax
  pshufb xmm1, [rip + splat]
  # create indices mask in xmm0
  vpcmpgtb xmm0, xmm1, [rip + indices]
  # load vector, apply mask, add len
  pand xmm0, [rdi]
  paddb xmm0, xmm1
  add rdi, rax
  
  jmp extra_loaded
extra0:
  movdqu xmm0, [rdi]
  add rdi, 16
extra_loaded:
  # load keys
  movdqa xmm3, [rip + key1]
  movdqa xmm4, [rip + key2]
  # initial vector (xmm1)
  movdqu xmm1, [rdi]
  cmp rsi, 32
  jbe final
  # fast path when input length > 32 and <= 48
  movdqu xmm2, [rdi + 16]
  aesenc xmm1, xmm2
  cmp rsi, 48
  jbe final
  # fast path when input length > 48 and <= 64
  movdqu xmm2, [rdi + 32]
  aesenc xmm1, xmm2
  cmp rsi, 64
  jbe final

  # compress many (length > 32)

  add rdi, 48
  # block compression end address (rbx)
  add rbx, rsi
  # unrollable bytes
  mov rax, rbx
  sub rax, rdi
  and rax, 127
  # jump to block compression if nothing unrollable
  cmp al, 0
  je compress8prep

  # unrollable compression

unrollable:
  movdqu xmm2, [rdi]
  aesenc xmm0, xmm2
  cmp al, 16
  je post_unrollable
  movdqu xmm2, [rdi + 16]
  aesenc xmm0, xmm2
  cmp al, 32
  je post_unrollable
  movdqu xmm2, [rdi + 32]
  aesenc xmm0, xmm2
  cmp al, 48
  je post_unrollable
  movdqu xmm2, [rdi + 48]
  aesenc xmm0, xmm2
  cmp al, 64
  je post_unrollable
  movdqu xmm2, [rdi + 64]
  aesenc xmm0, xmm2
  cmp al, 80
  je post_unrollable
  movdqu xmm2, [rdi + 80]
  aesenc xmm0, xmm2
  cmp al, 96
  je post_unrollable
  movdqu xmm2, [rdi + 96]
  aesenc xmm0, xmm2
  cmp al, 112
  je post_unrollable
  movdqu xmm2, [rdi + 112]
  aesenc xmm0, xmm2
post_unrollable:
  add rdi, rax

  # compress in blocks

compress8prep:
  # diasmbiguation vectors (xmm5 already zero)
  pxor xmm2, xmm2

  # save xmm1 (xmm0 overwritten, both for tmp registers)
  sub rsp, 16
  movdqa [rsp], xmm1

  # lanes
  movdqa xmm8, xmm0
  movdqa xmm9, xmm0

  # move address into RAX (smaller opcode)
  mov rax, rdi
  cmp rax, rbx
  je post_compress8
compress8:
  # compress into tmp registers
  movdqu xmm0, [rax]
  movdqu xmm1, [rax + 16]

  movdqu xmm6, [rax + 32]
  movdqu xmm7, [rax + 48]
  
  movdqu xmm10, [rax + 64]
  movdqu xmm11, [rax + 80]

  movdqu xmm12, [rax + 96]
  movdqu xmm13, [rax + 112]

  aesenc xmm0, xmm6
  aesenc xmm1, xmm7

  aesenc xmm0, xmm10
  aesenc xmm1, xmm11

  aesenc xmm0, xmm12
  aesenc xmm1, xmm13
  # add keys to disambiguation vectors
  paddb xmm2, xmm3
  paddb xmm5, xmm4
  # encrypt tmp registers using those vectors as keys
  aesenc xmm0, xmm2
  aesenc xmm1, xmm5
  # last encryption with lanes as keys
  vaesenclast xmm8, xmm0, xmm8
  vaesenclast xmm9, xmm1, xmm9
  # loop
  add rax, 128
  cmp rax, rbx
  jb compress8
post_compress8:
  # splat len on stack and load into xmm0
  and esi, 0xFFFFFFFF
  movd xmm0, esi
  pshufd xmm0, xmm0, 0x00

  # load xmm1
  movdqa xmm1, [rsp]
  add rsp, 16

  # add len to lanes
  paddb xmm8, xmm0
  paddb xmm9, xmm0

  # merge lanes
  vaesenc xmm0, xmm8, xmm9

  /*
  pxor xmm5, xmm5
  pxor xmm6, xmm6
  pxor xmm7, xmm7
  */
final:
  aesenc xmm1, xmm3
  aesenc xmm1, xmm4
  aesenclast xmm0, xmm1
  # cleanup
  /*
  pxor xmm1, xmm1
  pxor xmm2, xmm2
  pxor xmm3, xmm3
  pxor xmm4, xmm4
  */
  pop rbx
return:
  ret
ret0:
  pxor xmm0, xmm0
  ret

# partially load a vector (SAFE | copies if all 16 bytes don't fit into one page)
# rdi = address, rsi = length | uses xmm0-1, output in xmm0
get_partial:
  # check if all 16 bytes are on the same page
  mov ax, di
  not ax
  test ax, 4080 # 4096KiB - 16 (does the 16th byte exceed page boundary?)
  # jump to safe version if not
  je get_partial_safe
get_partial_unsafe:
  # splat len into xmm1
  movd xmm1, esi
  pshufb xmm1, [rip + splat]
  # create indices mask in xmm0
  vpcmpgtb xmm0, xmm1, [rip + indices]
  # load vector w/ mask, add len
  pand xmm0, [rdi] # may SIGSEGV!
  paddb xmm0, xmm1
  # cleanup
  ret
get_partial_safe:
  # splat len into xmm0
  movd xmm0, esi
  pshufb xmm0, [rip + splat]
  # align stack
  push rbp
  mov rbp, rsp
  and rsp, -32
  # partial copy vector onto stack
  mov rcx, rsi
  mov rsi, rdi
  mov rdi, rsp
  rep movsb
  # load via add len
  paddb xmm0, [rsp]
  # cleanup
  leave
  ret


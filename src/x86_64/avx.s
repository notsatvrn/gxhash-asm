.intel_syntax noprefix

.rodata
.p2align 4
# constant for get_partial_unsafe indices
indices: .byte 0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15
# keys
key1: .long 0xF2784542, 0xB09D3E21, 0x89C222E5, 0xFC3BC28E
key2: .long 0x03FCE279, 0xCB6B2E9B, 0xB361DC58, 0x39132BD9
key3: .long 0xD0012E32, 0x689D2B7D, 0x5544B1B7, 0xC78B122B

.text
.global hash_fast
.type hash_fast, @function

# quickly hash bytes
# rdi = address, rsi = length, rdx = seed | output in xmm0
hash_fast:
  # fast path for len == 0
  mov rax, rsi
  test rax, rax
  je ret0
  # some other hot paths
  cmp rax, 16
  jb get_partial
  ja over_16

  # fast path for len == 16

  # splat len
  movd xmm1, esi
  pxor xmm2, xmm2
  pshufb xmm1, xmm2
  # add len
  vpaddb xmm0, xmm1, [rdi]
  ret
over_16:
  # store initial address
  push rbx
  mov rbx, rdi
  # load initial hash vector (xmm0)
  and rax, 0xf
  je extra0
  
  # extra bytes was not 0 (get partial unsafe)
  
  # splat len
  movd xmm1, eax
  pxor xmm2, xmm2
  pshufb xmm1, xmm2
  # create indices mask
  vpcmpgtb xmm0, xmm1, [rip + indices]
  # load vector by applying mask, add len
  vpand xmm0, xmm0, [rdi]
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
  vaesenc xmm1, xmm1, [rdi + 16]
  cmp rsi, 48
  jbe final
  # fast path when input length > 48 and <= 64
  vaesenc xmm1, xmm1, [rdi + 32]
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
  jz compress8prep

  # unrollable compression

unrollable:
  vaesenc xmm0, xmm0, [rdi]
  cmp al, 16
  je post_unrollable
  vaesenc xmm0, xmm0, [rdi + 16]
  cmp al, 32
  je post_unrollable
  vaesenc xmm0, xmm0, [rdi + 32]
  cmp al, 48
  je post_unrollable
  vaesenc xmm0, xmm0, [rdi + 48]
  cmp al, 64
  je post_unrollable
  vaesenc xmm0, xmm0, [rdi + 64]
  cmp al, 80
  je post_unrollable
  vaesenc xmm0, xmm0, [rdi + 80]
  cmp al, 96
  je post_unrollable
  vaesenc xmm0, xmm0, [rdi + 96]
  cmp al, 112
  je post_unrollable
  vaesenc xmm0, xmm0, [rdi + 112]
post_unrollable:
  add rdi, rax

  # compress in blocks

compress8prep:
  # xmm1, 3-4 reserved
  # tmp registers: xmm0 and xmm14

  # disambiguation vectors
  pxor xmm2, xmm2
  pxor xmm5, xmm5
  # lanes
  movdqa xmm7, xmm0
  movdqa xmm8, xmm0
  # move address into RAX (smaller opcode)
  mov rax, rdi
  cmp rax, rbx
  je post_compress8
compress8:
  movdqu xmm0, [rax]
  movdqu xmm6, [rax + 16]
  vaesenc xmm0, xmm0, [rax + 32]
  vaesenc xmm6, xmm6, [rax + 48]
  vaesenc xmm0, xmm0, [rax + 64]
  vaesenc xmm6, xmm6, [rax + 80]
  vaesenc xmm0, xmm0, [rax + 96]
  vaesenc xmm6, xmm6, [rax + 112]
  # add keys to disambiguation vectors
  paddb xmm2, xmm3
  paddb xmm5, xmm4
  # encrypt tmp registers using those vectors as keys
  aesenc xmm0, xmm2
  aesenc xmm6, xmm5
  # last encryption with lanes as keys
  vaesenclast xmm7, xmm0, xmm7
  vaesenclast xmm8, xmm6, xmm8
  # loop
  add rax, 128
  cmp rax, rbx
  jb compress8
post_compress8:
  # splat len in xmm0
  movd xmm0, esi
  pshufd xmm0, xmm0, 0x00
  # add len to lanes
  paddb xmm8, xmm0
  paddb xmm0, xmm7
  # merge lanes
  aesenc xmm0, xmm8
final:
  aesenc xmm1, xmm3
  aesenc xmm1, xmm4
  aesenclast xmm0, xmm1
  pop rbx
  # create seed in xmm1
  movq xmm1, rdx
  movlhps xmm1, xmm1
  # encrypt
  aesenc xmm0, xmm1
  # finalize
  aesenc xmm0, xmm3
  aesenc xmm0, xmm4
  aesenclast xmm0, [rip + key3]
  ret
ret0:
  pxor xmm0, xmm0
  ret

# partially load a vector (SAFE | copies if all 16 bytes don't fit into one page)
# rdi = address, rsi = length | uses xmm0-2, output in xmm0
get_partial:
  pxor xmm2, xmm2
  # check if all 16 bytes are on the same page
  mov ax, di
  and ax, 0xFFF
  cmp ax, (0x1000 - 16)
  # jump to safe version if not
  jae get_partial_safe
get_partial_unsafe:
  # splat len
  movd xmm1, esi
  pshufb xmm1, xmm2
  # create indices mask
  vpcmpgtb xmm0, xmm1, [rip + indices]
  # load vector by applying mask, add len
  vpand xmm0, xmm0, [rdi] # may SIGSEGV!
  paddb xmm0, xmm1
  # cleanup
  ret
get_partial_safe:
  # splat len
  movd xmm0, esi
  pshufb xmm0, xmm2
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

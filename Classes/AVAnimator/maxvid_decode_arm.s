// This file implements the following C functions for the ARM platform.
// Both ARM6 and ARM7 devices are supported by this implementation.
//
// maxvid_decode_c4_sample16()
// maxvid_decode_c4_sample32()

// This ARM asm file will generate an error with clang 4 (xcode 4.5 and newer) because
// the integrated assembler does not accept AT&T syntax. This .s target will need to
// have the "-no-integrated-as" command line option passed via
// "Target" -> "Build Phases" -> "maxvid_decode_arm.s"

#if defined(__arm__)
# define COMPILE_ARM 1
# if defined(__thumb__)
#  define COMPILE_ARM_THUMB_ASM 1
# else
#  define COMPILE_ARM_ASM 1
# endif
#endif

// Xcode 4.2 supports clang only, but the ARM asm integration depends on specifics
// of register allocation and as a result only works when compiled with gcc.

#if defined(__clang__)
#  define COMPILE_CLANG 1
#endif // defined(__clang__)

// For CLANG build on ARM, skip this entire module and use custom ARM asm imp instead.

#if defined(COMPILE_CLANG) && defined(COMPILE_ARM)
# define USE_GENERATED_ARM_ASM 1
#endif // SKIP __clang__ && ARM

// GCC 4.2 and newer seems to allocate registers in a way that breaks the inline
// arm asm in maxvid_decode.c, so use the ARM asm in this case.

#if defined(__GNUC__) && !defined(__clang__) && defined(COMPILE_ARM)
# define __GNUC_PREREQ(maj, min) \
  ((__GNUC__ << 16) + __GNUC_MINOR__ >= ((maj) << 16) + (min))
# if __GNUC_PREREQ(4,2)
#  define USE_GENERATED_ARM_ASM 1
# endif
#endif

// This inline asm flag would only be used if USE_GENERATED_ARM_ASM was not defined

#if defined(COMPILE_ARM)
# define USE_INLINE_ARM_ASM 1
#endif

// It is possible one might want to actually compile the C code on an
// ARM system and simply not use the inline ASM blocks and let the
// compiler generate ARM code automatically. Set the argument
// value for this if to 1 to enable build on ARM without inline ASM.

#if 0 && defined(USE_GENERATED_ARM_ASM)
#undef USE_GENERATED_ARM_ASM
#undef USE_INLINE_ARM_ASM
#endif

// It is possible to compile this decoder module without the logic to
// make a call to the system defined memcpy() function. In the case
// where the system defined memcpy() is significantly faster for
// large copies this external call can speed things up. But, if
// it is slower or does not exist in a bare metal impl then this
// module can be compiled completely self contained by commenting
// out this define.

#define USE_SYSTEM_MEMCPY

#if defined(USE_GENERATED_ARM_ASM)
	.section __TEXT,__text,regular
	.section __TEXT,__textcoal_nt,coalesced
	.section __TEXT,__const_coal,coalesced
	.section __TEXT,__picsymbolstub4,symbol_stubs,none,16
	.text
	.align 2
	.arm
	.globl _maxvid_decode_c4_sample16
	.private_extern _maxvid_decode_c4_sample16
_maxvid_decode_c4_sample16:
	@ args = 0, pretend = 0, frame = 0
	@ frame_needed = 1, uses_anonymous_args = 0
	push {r4, r5, r6, r7, lr}
	add	r7, sp, #12
	push {r8, r10, r11}
	mov	r9, r1
	mov	r10, r0
	mov r8, #0
	
	mov r11, #1
	mvn r4, #0xC000
	orr r11, r11, r11, lsl #15
	mov r5, #2
	orr r5, r5, r11, lsr #1
	
	ldr r8, [r9], #4
	
	@ goto DECODE_16BPP

	b	LDECODE_16BPP

.align 3
LDUP_16BPP:
	@ DUP_16BPP
	
	tst r10, #3
	pkhbt r0, r8, r8, lsl #16
	subne ip, ip, #1
	strhne r8, [r10], #2

	// Note that the order here is to place a mov between str/ldr to
	// improvie dual issue. It is slower with the mov after the ldr.

	@ numWords
	mov lr, ip, lsr #1
	
	ldr r8, [r9], #4
	
	@ if (numWords > 6) goto DUPBIG_16BPP

	// Note that the specific instruction order took a lot of work to get
	// right since optimal execution performance on Cortex A8 and A9 is
	// really tricky. The key to getting a speedup on both processors is
	// to do an unconditional add after the second stm and then use a
	// negative offset on the final conditional store without a writeback
	// so that the next instruction in the decode block is not waiting on r10.

	cmp	lr, #6
	bhi	LDUPBIG_16BPP

	@ DUPSMALL_16BPP

	mov r1, r0

	// if (numWords >= 3) then write 3 words
	cmp lr, #2
	mov r2, r0
	subgt lr, lr, #3
	stmgt r10!, {r0, r1, r2}

	// if (numWords >= 2) then write 2 words
	cmp lr, #1
	stmgt r10, {r0, r1}
	// frameBuffer16 += numWords;
	add r10, r10, lr, lsl #2

	// if (numWords == 1 || numWords == 3) then write 1 word
	tst lr, #0x1
	strne r0, [r10, #-4]

	// if odd number of pixels, write a halfword
	tst ip, #1
	strhne r0, [r10], #2
	
	@ fall through to DECODE_16BPP

.align 3
LDECODE_16BPP:
	@ DECODE_16BPP

	@ if ((opCode = (inW1 >> 30)) == SKIP) ...
	movs r6, r8, lsr #30
	mov r2, r8, lsr #16
	beq LSKIP_16BPP

	@ if (COPY1 == (inW1 >> 16)) ...
	cmp r11, r2
	beq LCOPY1_16BPP

	@ if (DUP2 == (inW1 >> 16)) ...
	cmp r5, r2
	beq LDUP2_16BPP

	@ numPixels = (inW1 >> 16) & extractNumPixelsHighHalfWord;
	and ip, r4, r2

	@ if (opCode == DUP) goto DUP_16BPP
	
	cmp	r6, #2
	blt	LDUP_16BPP

	@ if (opCode == DONE) goto DONE_16BPP
	
	bgt	LDONE_16BPP

	@ COPY 16BPP

	@ align32
	tst r10, #3
	subne ip, ip, #1
	strhne r8, [r10], #2

	@ numWords
	mov lr, ip, lsr #1
  
	@ if (numWords > 7) goto COPYBIG_16BPP
	
	cmp	ip, #15
	bhi	LCOPYBIG_16BPP

	@ COPYSMALL_16BPP

	cmp lr, #3
	ldmgt r9!, {r0, r1, r2, r3}
	subgt lr, lr, #4
	stmgt r10!, {r0, r1, r2, r3}
	cmp lr, #1
	ldmgt r9!, {r0, r1}
	subgt lr, lr, #2
	stmgt r10!, {r0, r1}
	cmp lr, #1
	ldreq r0, [r9], #4
	streq r0, [r10], #4
	
	tst ip, #0x1
	ldrne r3, [r9], #4
	strhne r3, [r10], #2
	
	ldr r8, [r9], #4
	
	@ goto DECODE_16BPP
	b	LDECODE_16BPP

// Force each branch in the critical DECODE execution path
// to be 64 bit aligned. This avoids slower execution
// in the case where the instruction being branched to
// is not 64bit aligned.

.align 3
LSKIP_16BPP:
	@ SKIP_16BPP

	add r10, r10, r8, lsl #1
	ldr r8, [r9], #4

	@ goto DECODE_16BPP
	b LDECODE_16BPP

.align 3
LCOPY1_16BPP:
	@ COPY1_16BPP

	strh r8, [r10], #2
	ldr r8, [r9], #4

	@ goto DECODE_16BPP
	b LDECODE_16BPP

.align 3
LDUP2_16BPP:
	@ DUP2_16BPP

	strh r8, [r10], #2
	strh r8, [r10], #2
	ldr r8, [r9], #4

	@ goto DECODE_16BPP
	b LDECODE_16BPP

LCOPYBIG_16BPP:
	@ COPYBIG_16BPP

	@ Phantom assign to numWords

	// align64
	tst r10, #7
	ldrne r0, [r9], #4
	subne lr, lr, #1
	strne r0, [r10], #4
	// end align64

	// if (numPixels >= 16) do 8 word read/write loop
	cmp	lr, #15
	bls	L13

#if defined(USE_SYSTEM_MEMCPY)
	// if (numPixels >= 1024) call memcpy()
	cmp	ip, #1024
	bge	LHUGECOPY_16BPP
#endif // USE_SYSTEM_MEMCPY

1:
	ldm r9!, {r0, r1, r2, r3, r4, r5, r6, r8}
	pld	[r9, #32]
	sub lr, lr, #16
	stm r10!, {r0, r1, r2, r3, r4, r5, r6, r8}
	ldm r9!, {r0, r1, r2, r3, r4, r5, r6, r8}
	pld	[r9, #32]
	cmp lr, #15
	stm r10!, {r0, r1, r2, r3, r4, r5, r6, r8}
	bgt 1b
	
L13:
	cmp lr, #7
	ldmgt r9!, {r0, r1, r2, r3, r4, r5, r6, r8}
	subgt lr, lr, #8
	stmgt r10!, {r0, r1, r2, r3, r4, r5, r6, r8}
	cmp lr, #3
	ldmgt r9!, {r0, r1, r2, r3}
	subgt lr, lr, #4
	stmgt r10!, {r0, r1, r2, r3}
	cmp lr, #1
	ldmgt r9!, {r0, r1}
	subgt lr, lr, #2
	stmgt r10!, {r0, r1}
	cmp lr, #1
	ldreq r0, [r9], #4
	mov r5, #2
	streq r0, [r10], #4
	
	tst ip, #0x1
	ldrne r3, [r9], #4
	mvn r4, #0xC000
	strhne r3, [r10], #2
	
	ldr r8, [r9], #4

	orr r5, r5, r11, lsr #1
	
	@ goto DECODE_16BPP
	
	b	LDECODE_16BPP

#if defined(USE_SYSTEM_MEMCPY)

LHUGECOPY_16BPP:
	@ HUGECOPY_16BPP

	// registers:
	// r0-r3   : scratch, will not be restored
	// r4-r8   : function will restore these
	// r9      : will not be restored
	// r10-r11 : function will restore these
	// r12-r15 : will not be restored

	mov r4, r9
	// The r12 register (ip) gets blown away by the memcpy()
	// invocation, so it needs to be saved. This register
	// holds the number of pixels and is used to determine
	// if a trailing half word should be written.
	mov r5, r12
	// The r14 register (lr) gets blown away by the memcpy()
	// invocation, but it is not needed anymore. This
	// register is currently holding the number of words.
	mov r6, r14, lsl #2

	// memcpy(frameBuffer32, inputBuffer32, numPixels << 2);
	mov	r0, r10
	mov	r1, r9
	mov	r2, r6
	bl  _memcpy

	mov	r9, r4
	mov	r12, r5

	// inputBuffer32 += numPixels;
	add r9, r9, r6
	// frameBuffer32 += numPixels;
	add r10, r10, r6

	// One additional half word might need to be emitted
	tst ip, #0x1
	ldrne r3, [r9], #4
	strhne r3, [r10], #2

	ldr r8, [r9], #4

	mov r5, #2
	mvn r4, #0xC000
	// r11 should have been restored to the constant 32769
	orr r5, r5, r11, lsr #1

	@ goto DECODE_16BPP
	b LDECODE_16BPP

#endif // USE_SYSTEM_MEMCPY

LDUPBIG_16BPP:
	@ DUPBIG_16BPP

	// align64 scheduled with r1 init
	tst r10, #7
	mov r1, r0
	strne r0, [r10], #4
	subne lr, lr, #1
	// end align64

	mov r2, r0
	mov r3, r0

	// In the case where the 8 word loop will not be executed, skip forward
	// over the next 8 instructions. This provides a nice speed boost on A8
	// processors and is a little bit faster on A9 too.

	cmp lr, #8
	blt 2f

	mov r4, r0
	mov r5, r0
	mov r6, r0
	mov r8, r0
1:
	cmp lr, #15 // 7 + 8
	stm r10!, {r0, r1, r2, r3, r4, r5, r6, r8}
	sub lr, lr, #8
	bgt 1b
2:

	// The next set of instructions are ordered for max
	// execution performance on A8 and A9. The key is to
	// avoid register interlock as much as possible but
	// without accessing r10 early, as a previous stm 8
	// might not allow it. Like the fast logic from small
	// DUP, this code calculates the end of the write
	// so that writebacks are not needed on r10 at the end.

	// if (numWords > 3) then write 4 words
	cmp lr, #3
	mvn r4, #0xC000
	subgt lr, lr, #4
	stmgt r10!, {r0, r1, r2, r3}

	mov r5, #2
	// if (numWords > 2) then write 3 words
	// if (numWords == 2) then write 2 words
	cmp lr, #2
	orr r5, r5, r11, lsr #1
	stmgt r10, {r0, r1, r2}
	stmeq r10, {r0, r1}
	// frameBuffer16 += (numWords << 1)
	add r10, r10, lr, lsl #2

	// if (numWords == 1) then write 1 words
	cmp lr, #1
	ldr r8, [r9, #-4]
	streq r0, [r10, #-4]

	// if numPixels is odd then write 1 halfword
	tst ip, #1
	strhne r0, [r10], #2

	@ goto DECODE_16BPP
	
	b	LDECODE_16BPP

LDONE_16BPP:
	@ DONE_16BPP
	
	mov	r0, #0
	pop {r8, r10, r11}
	pop {r4, r5, r6, r7, pc}





	.align 2
	.arm
	.globl _maxvid_decode_c4_sample32
	.private_extern _maxvid_decode_c4_sample32
_maxvid_decode_c4_sample32:
	@ args = 0, pretend = 0, frame = 0
	@ frame_needed = 1, uses_anonymous_args = 0
	push {r4, r5, r6, r7, lr}
	add	r7, sp, #12
	push {r8, r10, r11}
	mov	r11, #0
	mov	r9, r1
	mov	r10, r0
	mov r8, #0
	mov lr, #0
	
	ldm r9!, {r8, lr}
	
	mov r3, #1
	mov r4, #6
	mov r5, #9
	mov r6, #3
	
	@ goto DECODE_32BPP
	
	b	LDECODE_32BPP

	// Explicit 64 bit alignment of the DUP block seems to improve performance for the
	// special case loop. It is unclear exactly why as disassembly indicates that the
	// first instruction of this block was already 64 bit aligned.

.align 3
LDUP_32BPP:
	@ DUP_32BPP

	// Note that the specific instruction order took a lot of work to get
	// right since optimal execution performance on Cortex A8 and A9 is
	// really tricky. In the small DUP case at 32BPP, only the numPixels
	// values 3, 4, 5, 6 are valid at this point since DUP 2 is handled
	// inline in the DECODE block. This impl will reorder instruction
	// execution to take advantage of dual issue and placing unconditional
	// instructions after a compare. This logic also avoids using r2 as
	// a stm write value so that lr can be used until lr is reloaded.

	mov ip, r8, lsr #10
	
	@ if (numWords > 6) goto DUPBIG_32BPP

	cmp	ip, #6
	bhi	LDUPBIG_32BPP

	@ DUPSMALL_32BPP

	mov r0, lr
	mov r1, lr

	// Unconditionally write 3 words (numPixels is 3, 4, 5, or 6)
	stm r10, {r0, r1, lr}
	add r2, r10, #12

	// if (numWords > 4) then write 2 words (numPixels is 5 or 6)
	cmp ip, #4
	// frameBuffer32 += numPixels;
	add r10, r10, ip, lsl #2
	stmgt r2, {r0, r1}

	// if (numWords == 4 || numWords == 6) then write 1 word
	tst ip, #0x1
	ldm r9!, {r8, lr}
	streq r0, [r10, #-4]
	
	@ fall through to DECODE_32BPP

	// Aligning the DECODE branch to 64 bits fixes a performance problem that only shows up in
	// the single special case op loop. This issue only appeared after mods to add a memcpy call.
	// This has something to do with the instruction cache alignment but it is unclear why
	// this align makes code execute more quickly on A9 but the same change makes the
	// 16 BPP block execute more slowly.

.align 3
LDECODE_32BPP:
	@ DECODE_32BPP

	// frameBuffer32 += skipAfter;
	add r10, r10, r11, lsl #2
	mov r2, r8, lsr #8
	and r11, r8, #0xFF

	// if ((inW1 >> 8) == copyOnePixelWord)
	cmp r4, r2
	beq LCOPY1_32BPP

	// if ((inW1 >> 8) == dupTwoPixelsWord)
	cmp r5, r2
	beq LDUP2_32BPP

	// if (opCode == SKIP)
	ands ip, r6, r2
	moveq r8, lr
	ldreq lr, [r9], #4
	// faster way to do r10 += (r11 << 2), only valid because we know
	// that a SKIP always has 0x0 as the value for the SKIP_AFTER byte.
	moveq r11, r2, lsr #2
	beq LDECODE_32BPP

	@ if (opCode == DUP) goto DUP_32BPP
	
	cmp	ip, #2
	blt	LDUP_32BPP

	@ if (opCode == DONE) goto DONE_32BPP

	bgt	LDONE_32BPP

	@ else (opCode == COPY) fallthrough

	rsb ip, r3, r2, lsr #2
	str lr, [r10], #4
	
	@ if (numWords > 7) goto COPYBIG_32BPP
	
	cmp	ip, #7
	bhi	LCOPYBIG_32BPP

	@ COPYSMALL_32BPP
	
	cmp ip, #3
	ldmgt r9!, {r0, r1, r2, r3}
	subgt ip, ip, #4
	stmgt r10!, {r0, r1, r2, r3}
	cmp ip, #1
	ldmgt r9!, {r0, r1}
	subgt ip, ip, #2
	stmgt r10!, {r0, r1}
	cmp ip, #1
	ldreq r0, [r9], #4
	streq r0, [r10], #4
	
	ldm r9!, {r8, lr}
	
	mov r3, #1
	
	@ goto DECODE_32BPP
	
	b	LDECODE_32BPP

// Force each branch in the critical DECODE execution path
// to be 64 bit aligned. This avoids slower execution
// in the case where the instruction being branched to
// is not 64bit aligned.

.align 3
LCOPY1_32BPP:
	@ COPY1_32BPP

	str lr, [r10], #4
	ldm r9!, {r8, lr}

	@ goto DECODE_32BPP
	b LDECODE_32BPP

.align 3
LDUP2_32BPP:
	@ DUP2_32BPP

	str lr, [r10]
	// The first instr of DECODE_32BPP does an add num words, so
	// use this little trick to avoid writing to r10 here. This
	// trick depends on add as opposed to mov because a DUP could
	// have set r11 to a SKIP_AFTER value.
	//add r10, r10, #8
	//str lr, [r10, #-4]
	add r11, r11, #8>>2
	str lr, [r10, #4]
	ldm r9!, {r8, lr}

	@ goto DECODE_32BPP
	b LDECODE_32BPP

LCOPYBIG_32BPP:
	@ COPYBIG_32BPP
	
	@ Phantom assign to numPixels

	// Note that align64 needs to go before cmp to branch past
	// the 8 word loop in the case where 16 would become 15.

	// align64
	tst r10, #7
	ldrne r0, [r9], #4
	subne ip, ip, #1
	strne r0, [r10], #4
	// end align64

	// if (numPixels >= 16) do 8 word read/write loop
	cmp	ip, #15
	bls	L33

#if defined(USE_SYSTEM_MEMCPY)
	// if (numPixels >= 1024) call memcpy()
	cmp	ip, #1024
	bge	LHUGECOPY_32BPP
#endif // USE_SYSTEM_MEMCPY

1:
	ldm r9!, {r0, r1, r2, r3, r4, r5, r6, r8}
	pld	[r9, #32]
	sub ip, ip, #16
	stm r10!, {r0, r1, r2, r3, r4, r5, r6, r8}
	ldm r9!, {r0, r1, r2, r3, r4, r5, r6, r8}
	pld	[r9, #32]
	cmp ip, #15
	stm r10!, {r0, r1, r2, r3, r4, r5, r6, r8}
	bgt 1b
	
L33:
	cmp ip, #7
	ldmgt r9!, {r0, r1, r2, r3, r4, r5, r6, r8}
	subgt ip, ip, #8
	stmgt r10!, {r0, r1, r2, r3, r4, r5, r6, r8}
	cmp ip, #3
	ldmgt r9!, {r0, r1, r2, r3}
	subgt ip, ip, #4
	stmgt r10!, {r0, r1, r2, r3}
	cmp ip, #1
	ldmgt r9!, {r0, r1}
	subgt ip, ip, #2
	stmgt r10!, {r0, r1}
	cmp ip, #1
	ldreq r0, [r9], #4
	mov r3, #1
	streq r0, [r10], #4

	mov r4, #6
	ldm r9!, {r8, lr}
	mov r5, #9
	mov r6, #3
	
	@ goto DECODE_32BPP
	
	b	LDECODE_32BPP

#if defined(USE_SYSTEM_MEMCPY)

LHUGECOPY_32BPP:
	@ HUGECOPY_32BPP

	// registers:
	// r0-r3   : scratch, will not be restored
	// r4-r8   : function will restore these
	// r9      : will not be restored
	// r10-r11 : function will restore these
	// r12-r15 : will not be restored

	mov r4, r9
	mov r5, r12 // aka ip
	mov r6, r12, lsl #2

	// memcpy(frameBuffer32, inputBuffer32, numPixels << 2);
	mov	r0, r10
	mov	r1, r9
	mov	r2, r6
	bl  _memcpy

	mov	r9, r4
	mov	r12, r5

	// inputBuffer32 += numPixels;
	add r9, r9, r6
	// frameBuffer32 += numPixels;
	add r10, r10, r6

	ldm r9!, {r8, lr}

	mov r3, #1
	mov r4, #6
	mov r5, #9
	mov r6, #3

	@ goto DECODE_32BPP
	b LDECODE_32BPP

#endif // USE_SYSTEM_MEMCPY

LDUPBIG_32BPP:
	@ DUPBIG_32BPP

	// Note that this r0 init and the loading of r8, lr were pulled into this
	// block as a result of wanting to optimize DUPSMALL.
	mov r0, lr
	ldm r9!, {r8, lr}

	// align64 scheduled with wr2 init
	tst r10, #7
	mov r1, r0
	strne r0, [r10], #4
	subne ip, ip, #1
	// end align64

	mov r2, r0
	mov r3, r0
	// Note that this lr init does not appear in the inline ASM code from the C file
	mov lr, r8

	// In the case where the 8 word loop will not be executed, skip forward
	// over the next 8 instructions. This provides a nice speed boost on A8
	// processors and is a little bit faster on A9 too.

	cmp ip, #8
	blt 2f

	mov r4, r0
	mov r5, r0
	mov r6, r0
	mov r8, r0
1:
	cmp ip, #15 // 7 + 8
	stm r10!, {r0, r1, r2, r3, r4, r5, r6, r8}
	sub ip, ip, #8
	bgt 1b
2:

	// The next set of instructions are scheduled for max
	// execution performance on A8 and A9. The key is to
	// avoid register interlock as much as possible but
	// without accessing r10 early, as a previous stm 8
	// might not allow it. This logic mixes constant stores
	// at the end into the store logic.

	// if (numWords > 3) then write 4 words
	cmp ip, #3
	mov r4, #6
	subgt ip, ip, #4
	stmgt r10!, {r0, r1, r2, r3}

	// if (numWords > 2) then write 3 words
	// if (numWords == 2) then write 2 words
	mov r5, #9
	cmp ip, #2
	mov r6, #3
	stmgt r10, {r0, r1, r2}
	stmeq r10, {r0, r1}
	// frameBuffer32 += (numWords << 1)
	add r10, r10, ip, lsl #2

	// if (numWords == 1) then write 1 words
	cmp ip, #1
	mov r3, #1
	streq r0, [r10, #-4]

	mov r8, lr
	ldr lr, [r9, #-4]
	
	@ goto DECODE_32BPP
	
	b	LDECODE_32BPP

LDONE_32BPP:
	@ DONE_32BPP
	
	mov	r0, #0
	pop {r8, r10, r11}
	pop {r4, r5, r6, r7, pc}

	.subsections_via_symbols

#else
  // No-op when USE_GENERATED_ARM_ASM is not defined
#endif

# Makefile

include config.mak

vpath %.c $(SRCPATH)
vpath %.h $(SRCPATH)
vpath %.S $(SRCPATH)
vpath %.asm $(SRCPATH)
vpath %.rc $(SRCPATH)

GENERATED =

all: default
default:

# SRCS: compiled exactly once regardless of which bit depth(s) are selected.
# base.c/tables.c/api.c are new (bitdepth-unify backport); cpu.c and osdep.c
# were already single-compile in the pre-backport Makefile and still are,
# since common/cpu.h and common/osdep.h were never templated.
SRCS = common/osdep.c common/base.c common/cpu.c common/tables.c \
       encoder/api.c

# SRCS_X: compiled once PER SELECTED BIT DEPTH (suffixed -8.o / -10.o below),
# since every symbol here is templated via x264_template()/BIT_DEPTH and
# would otherwise collide across the two depths' object files.
SRCS_X = common/mc.c common/predict.c common/pixel.c common/macroblock.c \
         common/frame.c common/dct.c common/cabac.c \
         common/common.c common/rectangle.c \
         common/set.c common/quant.c common/deblock.c common/vlc.c \
         common/mvpred.c common/bitstream.c \
         encoder/analyse.c encoder/me.c encoder/ratecontrol.c \
         encoder/set.c encoder/macroblock.c encoder/cabac.c \
         encoder/speed.c \
         encoder/cavlc.c encoder/encoder.c encoder/lookahead.c

# SRCS_8: like SRCS_X, but compiled ONLY into the -8.o pass even when both
# depths are selected (e.g. OpenCL: upstream self-gates it to BIT_DEPTH==8
# via HAVE_OPENCL's define, see configure).
SRCS_8 =

SRCCLI = x264.c input/input.c input/timecode.c input/raw.c input/y4m.c \
         output/raw.c output/matroska.c output/matroska_ebml.c \
         output/flv.c output/flv_bytestream.c filters/filters.c \
         filters/video/video.c filters/video/source.c filters/video/internal.c \
         filters/video/resize.c filters/video/fix_vfr_pts.c \
         filters/video/select_every.c filters/video/crop.c

# SRCCLI_X: like SRCS_X, but for the CLI -- these register a depth-specific
# filter/input name (e.g. "cache_8"/"cache_10") so both can coexist in the
# same binary; compiled once per selected depth into -8.o/-10.o below.
SRCCLI_X = filters/video/cache.c filters/video/depth.c

# SRCCHK_X: like SRCS_X, but for checkasm -- compiled once per depth so a
# separate checkasm8/checkasm10 binary can each test that depth's internal
# (non-public-API) functions directly. example.c is NOT updated (still out
# of scope; the `example` target is not expected to link).
SRCCHK_X = tools/checkasm.c

SRCSO =
OBJS =
OBJASM =
OBJSO =
OBJCLI =

OBJCHK =
OBJCHK_8 =
OBJCHK_10 =

CONFIG := $(shell cat config.h)

# GPL-only files
ifneq ($(findstring HAVE_GPL 1, $(CONFIG)),)
SRCCLI +=
endif

# Optional module sources
ifneq ($(findstring HAVE_AVS 1, $(CONFIG)),)
SRCCLI += input/avs.c
endif

ifneq ($(findstring HAVE_THREAD 1, $(CONFIG)),)
SRCCLI_X += input/thread.c
SRCS_X   += common/threadpool.c
endif

ifneq ($(findstring HAVE_WIN32THREAD 1, $(CONFIG)),)
SRCS += common/win32thread.c
endif

ifneq ($(findstring HAVE_LAVF 1, $(CONFIG)),)
SRCCLI += input/lavf.c
endif

ifneq ($(findstring HAVE_FFMS 1, $(CONFIG)),)
SRCCLI += input/ffms.c
endif

ifneq ($(findstring HAVE_GPAC 1, $(CONFIG)),)
SRCCLI += output/mp4.c
endif

ifneq ($(findstring HAVE_LSMASH 1, $(CONFIG)),)
SRCCLI += output/mp4_lsmash.c
endif

# MMX/SSE optims
# X86_64-only (configure refuses any other ARCH once bit-depth-unify is in
# the tree, see configure's ARCH check next to HAVE_BITDEPTH8/10).
ifneq ($(AS),)
ARCH_X86 = yes
ASFLAGS += -DARCH_X86_64=1 -I$(SRCPATH)/common/x86/

# Templated: same source, different code per HIGH_BIT_DEPTH pass, so each
# must be assembled once per selected depth (BIT_DEPTH=N, private_prefix=x264_N)
# to get uniquely-named symbols. Mirrors the equivalent common.h C templating.
SRCASM_X = common/x86/const-a.asm common/x86/cabac-a.asm \
           common/x86/dct-a.asm common/x86/dct-64.asm common/x86/deblock-a.asm \
           common/x86/mc-a.asm common/x86/mc-a2.asm \
           common/x86/pixel-a.asm common/x86/predict-a.asm \
           common/x86/quant-a.asm common/x86/bitstream-a.asm \
           common/x86/trellis-64.asm
SRCS_X  += common/x86/mc-c.c common/x86/predict-c.c

# Not templated: cpu detection has no per-bitdepth variation (common/cpu.h
# was never given the x264_template() treatment), so it keeps the plain
# "x264" private_prefix and is assembled exactly once regardless of which
# depth(s) are selected.
OBJASM = common/x86/cpu-a.o

# sad-a.asm / sad16-a.asm are two separate hardcoded-depth files (not one
# HIGH_BIT_DEPTH-branching source), so each is only ever assembled for its
# own matching pass, not both.
ifneq ($(findstring HAVE_BITDEPTH8 1, $(CONFIG)),)
OBJASM += $(SRCASM_X:%.asm=%-8.o) common/x86/sad-a-8.o
endif
ifneq ($(findstring HAVE_BITDEPTH10 1, $(CONFIG)),)
OBJASM += $(SRCASM_X:%.asm=%-10.o) common/x86/sad16-a-10.o
endif

$(OBJASM): common/x86/x86inc.asm common/x86/x86util.asm
OBJCHK += tools/checkasm-a.o
endif

# AltiVec optims
ifeq ($(ARCH),PPC)
ifneq ($(AS),)
SRCS += common/ppc/mc.c common/ppc/pixel.c common/ppc/dct.c \
        common/ppc/quant.c common/ppc/deblock.c \
        common/ppc/predict.c
endif
endif

# NEON optims
ifeq ($(ARCH),ARM)
ifneq ($(AS),)
ASMSRC += common/arm/cpu-a.S common/arm/pixel-a.S common/arm/mc-a.S \
          common/arm/dct-a.S common/arm/quant-a.S common/arm/deblock-a.S \
          common/arm/predict-a.S
SRCS   += common/arm/mc-c.c common/arm/predict-c.c
OBJASM  = $(ASMSRC:%.S=%.o)
endif
endif

# VIS optims
ifeq ($(ARCH),UltraSPARC)
ifeq ($(findstring HIGH_BIT_DEPTH, $(CONFIG)),)
ASMSRC += common/sparc/pixel.asm
OBJASM  = $(ASMSRC:%.asm=%.o)
endif
endif

ifneq ($(HAVE_GETOPT_LONG),1)
SRCCLI += extras/getopt.c
endif

ifeq ($(SYS),WINDOWS)
OBJCLI += $(if $(RC), x264res.o)
ifneq ($(SONAME),)
SRCSO  += x264dll.c
OBJSO  += $(if $(RC), x264res.dll.o)
endif
endif

ifeq ($(HAVE_OPENCL),yes)
common/oclobj.h: common/opencl/x264-cl.h $(wildcard $(SRCPATH)/common/opencl/*.cl)
	cat $^ | perl $(SRCPATH)/tools/cltostr.pl x264_opencl_source > $@
GENERATED += common/oclobj.h
SRCS_8 += common/opencl.c encoder/slicetype-cl.c
endif

OBJS   += $(SRCS:%.c=%.o)
OBJCLI += $(SRCCLI:%.c=%.o)
OBJSO  += $(SRCSO:%.c=%.o)

# SRCS_X/SRCCLI_X/SRCCHK_X are compiled once per selected bit depth into
# -8.o/-10.o objects (see the %-8.o/%-10.o pattern rules below), mirroring
# OBJASM above.
ifneq ($(findstring HAVE_BITDEPTH8 1, $(CONFIG)),)
OBJS     += $(SRCS_X:%.c=%-8.o) $(SRCS_8:%.c=%-8.o)
OBJCLI   += $(SRCCLI_X:%.c=%-8.o)
OBJCHK_8 += $(SRCCHK_X:%.c=%-8.o)
endif
ifneq ($(findstring HAVE_BITDEPTH10 1, $(CONFIG)),)
OBJS      += $(SRCS_X:%.c=%-10.o)
OBJCLI    += $(SRCCLI_X:%.c=%-10.o)
OBJCHK_10 += $(SRCCHK_X:%.c=%-10.o)
endif

.PHONY: all default fprofiled clean distclean install uninstall lib-static lib-shared cli install-lib-dev install-lib-static install-lib-shared install-cli

cli: x264$(EXE)
lib-static: $(LIBX264)
lib-shared: $(SONAME)

$(LIBX264): $(GENERATED) .depend $(OBJS) $(OBJASM)
	rm -f $(LIBX264)
	$(AR)$@ $(OBJS) $(OBJASM)
	$(if $(RANLIB), $(RANLIB) $@)

$(SONAME): $(GENERATED) .depend $(OBJS) $(OBJASM) $(OBJSO)
	$(LD)$@ $(OBJS) $(OBJASM) $(OBJSO) $(SOFLAGS) $(LDFLAGS)

ifneq ($(EXE),)
.PHONY: x264 checkasm8 checkasm10
x264: x264$(EXE)
ifneq ($(findstring HAVE_BITDEPTH8 1, $(CONFIG)),)
checkasm8: checkasm8$(EXE)
endif
ifneq ($(findstring HAVE_BITDEPTH10 1, $(CONFIG)),)
checkasm10: checkasm10$(EXE)
endif
endif

x264$(EXE): $(GENERATED) .depend $(OBJCLI) $(CLI_LIBX264)
	$(LD)$@ $(OBJCLI) $(CLI_LIBX264) $(LDFLAGSCLI) $(LDFLAGS)

# Each checkasm binary links the FULL library (both depths, when both are
# selected) plus its own depth-specific checkasm-N.o, since that object is
# what actually calls the x264_8_*/x264_10_* internal functions directly.
checkasm8$(EXE): $(GENERATED) .depend $(OBJCHK) $(OBJCHK_8) $(LIBX264)
	$(LD)$@ $(OBJCHK) $(OBJCHK_8) $(LIBX264) $(LDFLAGS)

checkasm10$(EXE): $(GENERATED) .depend $(OBJCHK) $(OBJCHK_10) $(LIBX264)
	$(LD)$@ $(OBJCHK) $(OBJCHK_10) $(LIBX264) $(LDFLAGS)

$(OBJS) $(OBJASM) $(OBJSO) $(OBJCLI) $(OBJCHK) $(OBJCHK_8) $(OBJCHK_10): .depend

# Explicit .c rule (was previously left to make's builtin implicit rule);
# needed now so it doesn't shadow/conflict with the %-8.o/%-10.o rules below.
%.o: %.c
	$(CC) $(CFLAGS) -c $(CC_O) $<

# SRCS_X objects: same source, compiled once per selected bit depth with
# BIT_DEPTH overridden so common.h's x264_template()/QP_MAX/PIXEL_MAX/etc
# macros pick the right depth for that pass.
%-8.o: %.c
	$(CC) $(CFLAGS) -DHIGH_BIT_DEPTH=0 -DBIT_DEPTH=8 -c $(CC_O) $<

%-10.o: %.c
	$(CC) $(CFLAGS) -DHIGH_BIT_DEPTH=1 -DBIT_DEPTH=10 -c $(CC_O) $<

%.o: %.asm
	$(AS) $(ASFLAGS) -o $@ $<
	-@ $(if $(STRIP), $(STRIP) -x $@) # delete local/anonymous symbols, so they don't show up in oprofile

# SRCASM_X objects: same source, assembled once per selected bit depth.
# private_prefix drives x86inc.asm's cglobal/mangle naming (see osdep.h's
# %ifndef private_prefix default) so each pass's symbols come out as
# x264_8_foo / x264_10_foo, matching what common.h's C-side templating
# expects to link against.
%-8.o: %.asm common/x86/x86inc.asm common/x86/x86util.asm
	$(AS) $(ASFLAGS) -o $@ $< -DBIT_DEPTH=8 -Dprivate_prefix=x264_8
	-@ $(if $(STRIP), $(STRIP) -x $@)

%-10.o: %.asm common/x86/x86inc.asm common/x86/x86util.asm
	$(AS) $(ASFLAGS) -o $@ $< -DBIT_DEPTH=10 -Dprivate_prefix=x264_10
	-@ $(if $(STRIP), $(STRIP) -x $@)

%.o: %.S
	$(AS) $(ASFLAGS) -o $@ $<
	-@ $(if $(STRIP), $(STRIP) -x $@) # delete local/anonymous symbols, so they don't show up in oprofile

%.dll.o: %.rc x264.h
	$(RC) $(RCFLAGS)$@ -DDLL $<

%.o: %.rc x264.h
	$(RC) $(RCFLAGS)$@ $<

.depend: config.mak
	@rm -f .depend
	@$(foreach SRC, $(addprefix $(SRCPATH)/, $(SRCS) $(SRCCLI) $(SRCSO)), $(CC) $(CFLAGS) $(SRC) $(DEPMT) $(SRC:$(SRCPATH)/%.c=%.o) $(DEPMM) 1>> .depend;)
ifneq ($(findstring HAVE_BITDEPTH8 1, $(CONFIG)),)
	@$(foreach SRC, $(addprefix $(SRCPATH)/, $(SRCS_X) $(SRCS_8) $(SRCCLI_X) $(SRCCHK_X)), $(CC) $(CFLAGS) $(SRC) $(DEPMT) $(SRC:$(SRCPATH)/%.c=%-8.o) $(DEPMM) 1>> .depend;)
endif
ifneq ($(findstring HAVE_BITDEPTH10 1, $(CONFIG)),)
	@$(foreach SRC, $(addprefix $(SRCPATH)/, $(SRCS_X) $(SRCCLI_X) $(SRCCHK_X)), $(CC) $(CFLAGS) $(SRC) $(DEPMT) $(SRC:$(SRCPATH)/%.c=%-10.o) $(DEPMM) 1>> .depend;)
endif

config.mak:
	./configure

depend: .depend
ifneq ($(wildcard .depend),)
include .depend
endif

SRC2 = $(SRCS) $(SRCCLI)
# These should cover most of the important codepaths
OPT0 = --crf 30 -b1 -m1 -r1 --me dia --no-cabac --direct temporal --ssim --no-weightb
OPT1 = --crf 16 -b2 -m3 -r3 --me hex --no-8x8dct --direct spatial --no-dct-decimate -t0  --slice-max-mbs 50
OPT2 = --crf 26 -b4 -m5 -r2 --me hex --cqm jvt --nr 100 --psnr --no-mixed-refs --b-adapt 2 --slice-max-size 1500
OPT3 = --crf 18 -b3 -m9 -r5 --me umh -t1 -A all --b-pyramid normal --direct auto --no-fast-pskip --no-mbtree
OPT4 = --crf 22 -b3 -m7 -r4 --me esa -t2 -A all --psy-rd 1.0:1.0 --slices 4
OPT5 = --frames 50 --crf 24 -b3 -m10 -r3 --me tesa -t2
OPT6 = --frames 50 -q0 -m9 -r2 --me hex -Aall
OPT7 = --frames 50 -q0 -m2 -r1 --me hex --no-cabac

ifeq (,$(VIDS))
fprofiled:
	@echo 'usage: make fprofiled VIDS="infile1 infile2 ..."'
	@echo 'where infiles are anything that x264 understands,'
	@echo 'i.e. YUV with resolution in the filename, y4m, or avisynth.'
else
fprofiled:
	$(MAKE) clean
	$(MAKE) x264$(EXE) CFLAGS="$(CFLAGS) $(PROF_GEN_CC)" LDFLAGS="$(LDFLAGS) $(PROF_GEN_LD)"
	$(foreach V, $(VIDS), $(foreach I, 0 1 2 3 4 5 6 7, ./x264$(EXE) $(OPT$I) --threads 1 $(V) -o $(DEVNULL) ;))
	rm -f $(SRC2:%.c=%.o)
	$(MAKE) CFLAGS="$(CFLAGS) $(PROF_USE_CC)" LDFLAGS="$(LDFLAGS) $(PROF_USE_LD)"
	rm -f $(SRC2:%.c=%.gcda) $(SRC2:%.c=%.gcno) *.dyn pgopti.dpi pgopti.dpi.lock
endif

clean:
	rm -f $(OBJS) $(OBJASM) $(OBJCLI) $(OBJSO) $(SONAME) *.a *.lib *.exp *.pdb x264 x264.exe .depend TAGS
	rm -f checkasm8 checkasm8.exe checkasm10 checkasm10.exe $(OBJCHK) $(OBJCHK_8) $(OBJCHK_10) $(GENERATED) x264_lookahead.clbin
	rm -f $(SRC2:%.c=%.gcda) $(SRC2:%.c=%.gcno) *.dyn pgopti.dpi pgopti.dpi.lock

distclean: clean
	rm -f config.mak x264_config.h config.h config.log x264.pc x264.def

install-cli: cli
	$(INSTALL) -d $(DESTDIR)$(bindir)
	$(INSTALL) x264$(EXE) $(DESTDIR)$(bindir)

install-lib-dev:
	$(INSTALL) -d $(DESTDIR)$(includedir)
	$(INSTALL) -d $(DESTDIR)$(libdir)
	$(INSTALL) -d $(DESTDIR)$(libdir)/pkgconfig
	$(INSTALL) -m 644 $(SRCPATH)/x264.h $(DESTDIR)$(includedir)
	$(INSTALL) -m 644 x264_config.h $(DESTDIR)$(includedir)
	$(INSTALL) -m 644 x264.pc $(DESTDIR)$(libdir)/pkgconfig

install-lib-static: lib-static install-lib-dev
	$(INSTALL) -m 644 $(LIBX264) $(DESTDIR)$(libdir)
	$(if $(RANLIB), $(RANLIB) $(DESTDIR)$(libdir)/$(LIBX264))

install-lib-shared: lib-shared install-lib-dev
ifneq ($(IMPLIBNAME),)
	$(INSTALL) -d $(DESTDIR)$(bindir)
	$(INSTALL) -m 755 $(SONAME) $(DESTDIR)$(bindir)
	$(INSTALL) -m 644 $(IMPLIBNAME) $(DESTDIR)$(libdir)
else ifneq ($(SONAME),)
	ln -f -s $(SONAME) $(DESTDIR)$(libdir)/libx264.$(SOSUFFIX)
	$(INSTALL) -m 755 $(SONAME) $(DESTDIR)$(libdir)
endif

uninstall:
	rm -f $(DESTDIR)$(includedir)/x264.h $(DESTDIR)$(includedir)/x264_config.h $(DESTDIR)$(libdir)/libx264.a
	rm -f $(DESTDIR)$(bindir)/x264$(EXE) $(DESTDIR)$(libdir)/pkgconfig/x264.pc
ifneq ($(IMPLIBNAME),)
	rm -f $(DESTDIR)$(bindir)/$(SONAME) $(DESTDIR)$(libdir)/$(IMPLIBNAME)
else ifneq ($(SONAME),)
	rm -f $(DESTDIR)$(libdir)/$(SONAME) $(DESTDIR)$(libdir)/libx264.$(SOSUFFIX)
endif

etags: TAGS

TAGS:
	etags $(SRCS) $(SRCS_X) $(SRCS_8)

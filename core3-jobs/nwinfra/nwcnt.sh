#!/bin/sh
# Liveness-counter patch for COUNTER builds only (never timed, never merged), on a tree with the
# whole wip/x264-nw-infra series. At exit the encoder prints to stderr:
#   NWCNT dual <n> vc <n> lowres_pad <n> sides_fld <n> sides_frm <n> slice0_caller <n>
#         kf_analyse_thread <n> kf_analyse_sync <n> pool_signal <n>
#         hpel_pad plain <n> copy <n> copy_vc <n> dual <n> ptrs dual <a> pad <a> sides <a>
# dual / vc: hpel_filter_dual / hpel_filter_copy_vc calls (adaptive MBAFF, when the _pad kernels are off);
# hpel_pad: hpel_filter_pad[mode] calls (the dispatched path at the tip; dual/copy_vc then run as pad modes 3/2);
# lowres_pad: frame_init_lowres_core_pad; sides_fld / sides_frm: expand_border_sides with / without the field
# planes; slice0_caller: lowres frame costs whose slice 0 ran on the caller (lookahead threads > 1);
# kf_analyse_thread / _sync: I-frame mbtree/VBV analyses in the lookahead thread (outside ofbuf.mutex) /
# without a lookahead thread; pool_signal: threadpool run/uninit pushes (one cond_signal each).
# <a>: the pointer called; map with nm x264 | grep -E 'hpel_filter_dual|lowres_core_pad|expand_border_sides'.
set -e
cd "$1"
if grep -q x264_nwcnt common/common.h; then echo "already patched"; exit 0; fi
awk '{ l[NR] = $0 } END { for( i = 1; i <= NR; i++ ) { if( i == NR ) print "extern long x264_nwcnt[14];\nextern void *x264_nwptr[3];"; print l[i] } }' common/common.h > common/c.tmp && mv common/c.tmp common/common.h
cat >> common/mc.c <<'EOF'
long x264_nwcnt[14];
void *x264_nwptr[3];
static void __attribute__((destructor)) nwcnt_print( void )
{
    fprintf( stderr, "NWCNT dual %ld vc %ld lowres_pad %ld sides_fld %ld sides_frm %ld slice0_caller %ld kf_analyse_thread %ld kf_analyse_sync %ld pool_signal %ld"
             " hpel_pad plain %ld copy %ld copy_vc %ld dual %ld ptrs dual %p pad %p sides %p\n",
             x264_nwcnt[0], x264_nwcnt[1], x264_nwcnt[2], x264_nwcnt[3], x264_nwcnt[4], x264_nwcnt[5], x264_nwcnt[6], x264_nwcnt[7], x264_nwcnt[8],
             x264_nwcnt[10], x264_nwcnt[11], x264_nwcnt[12], x264_nwcnt[13], x264_nwptr[0], x264_nwptr[1], x264_nwptr[2] );
}
EOF
C='__atomic_fetch_add( \&x264_nwcnt'
sed -i "s|^\( *\)h->mc.hpel_filter_dual( dsth|\1$C[0], 1, __ATOMIC_RELAXED ), x264_nwptr[0] = (void*)h->mc.hpel_filter_dual, h->mc.hpel_filter_dual( dsth|" common/mc.c
sed -i "s|^\( *\)h->mc.hpel_filter_copy_vc( dsth|\1$C[1], 1, __ATOMIC_RELAXED ), h->mc.hpel_filter_copy_vc( dsth|" common/mc.c
sed -i "s|^\( *\)h->mc.hpel_filter_pad\[b_copy\](|\1$C[10 + b_copy], 1, __ATOMIC_RELAXED ), h->mc.hpel_filter_pad[b_copy](|" common/mc.c
sed -i "s|^\( *\)h->mc.hpel_filter_pad\[3\*b_dual\](|\1$C[10 + 3*b_dual], 1, __ATOMIC_RELAXED ), x264_nwptr[0] = (void*)h->mc.hpel_filter_pad[3*b_dual], h->mc.hpel_filter_pad[3*b_dual](|" common/mc.c
sed -i "s|^\( *\)h->mc.frame_init_lowres_core_pad( frame|\1$C[2], 1, __ATOMIC_RELAXED ), x264_nwptr[1] = (void*)h->mc.frame_init_lowres_core_pad, h->mc.frame_init_lowres_core_pad( frame|" common/mc.c
sed -i "s|^\( *\)h->mc.expand_border_sides( pix_frm, pix,|\1$C[3], 1, __ATOMIC_RELAXED ); x264_nwptr[2] = (void*)h->mc.expand_border_sides;\n\1h->mc.expand_border_sides( pix_frm, pix,|" common/frame.c
sed -i "s|^\( *\)h->mc.expand_border_sides( pix, NULL,|\1$C[4], 1, __ATOMIC_RELAXED ); x264_nwptr[2] = (void*)h->mc.expand_border_sides;\n\1h->mc.expand_border_sides( pix, NULL,|" common/frame.c
sed -i "s|^\( *\)x264_stack_align( x264_slicetype_slice_cost, &s\[0\] );|\1$C[5], 1, __ATOMIC_RELAXED );\n&|" encoder/slicetype.c
sed -i "s|^        x264_stack_align( x264_slicetype_analyse, h, shift_frames );|        $C[6], 1, __ATOMIC_RELAXED ), x264_stack_align( x264_slicetype_analyse, h, shift_frames );|" encoder/lookahead.c
sed -i "s|^            x264_stack_align( x264_slicetype_analyse, h, shift_frames );|            $C[7], 1, __ATOMIC_RELAXED ), x264_stack_align( x264_slicetype_analyse, h, shift_frames );|" encoder/lookahead.c
sed -i "s|^    x264_pthread_cond_signal( &slist->cv_fill );|    $C[8], 1, __ATOMIC_RELAXED );\n&|" common/threadpool.c
n=$(grep -c "x264_nwcnt\[" common/mc.c common/frame.c encoder/slicetype.c encoder/lookahead.c common/threadpool.c | awk -F: '{s+=$2} END {print s}')
# 11 sites + the definition and 2 printer lines in mc.c
[ "$n" = 14 ] || { echo "patch did not apply ($n)"; grep -n "x264_nwcnt\[" common/mc.c common/frame.c encoder/slicetype.c encoder/lookahead.c common/threadpool.c; exit 1; }
echo "nwcnt patched"

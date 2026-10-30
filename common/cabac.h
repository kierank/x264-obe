/*****************************************************************************
 * cabac.h: arithmetic coder
 *****************************************************************************
 * Copyright (C) 2003-2014 x264 project
 *
 * Authors: Loren Merritt <lorenm@u.washington.edu>
 *          Laurent Aimar <fenrir@via.ecp.fr>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02111, USA.
 *
 * This program is also available under a commercial proprietary license.
 * For more information, contact us at licensing@x264.com.
 *****************************************************************************/

#ifndef X264_CABAC_H
#define X264_CABAC_H

typedef struct
{
    /* state */
    int i_low;
    int i_range;

    /* bit stream */
    int i_queue; //stored with an offset of -8 for faster asm
    int i_bytes_outstanding;

    uint8_t *p_start;
    uint8_t *p;
    uint8_t *p_end;

    /* aligned for memcpy_aligned starting here */
    ALIGNED_64( int f8_bits_encoded ); // only if using x264_cabac_size_decision()

    /* context */
    uint8_t state[1024];

    /* for 16-byte alignment */
    uint8_t padding[12];
} x264_cabac_t;

/* The written syntax of an MB before its residual, for bsf.cabac_mb_header:
 * end_of_slice_flag, mb_skip_flag, mb_field_decoding_flag, mb_type, sub_mb_type,
 * ref_idx, mvd, the intra modes, coded_block_pattern, transform_size_8x8_flag and
 * mb_qp_delta. Mirrored by struc mbhdr in common/x86/cabac-a.asm. */
#define CABAC_HDR_TERM          (1<<0)  /* end_of_slice_flag 0 first */
#define CABAC_HDR_SKIPFLAG      (1<<1)  /* mb_skip_flag (P and B slices) */
#define CABAC_HDR_BSLICE        (1<<2)
#define CABAC_HDR_SKIP          (1<<3)  /* skipped: mb_skip_flag 1 and nothing else */
#define CABAC_HDR_FIELD         (1<<4)  /* mb_field_decoding_flag */
#define CABAC_HDR_FIELD_CTX_SHIFT  5    /* its ctxIdxInc, bits 5-6 */
#define CABAC_HDR_FIELD_VAL     (1<<7)
#define CABAC_HDR_INTRA         (1<<8)  /* I_4x4, I_8x8 or I_16x16 */
#define CABAC_HDR_I16           (1<<9)
#define CABAC_HDR_T8X8_HDR      (1<<10) /* I_NxN: transform_size_8x8_flag before the modes */
#define CABAC_HDR_T8X8          (1<<11) /* b_transform_8x8 */
#define CABAC_HDR_T8X8_OK       (1<<12) /* transform_size_8x8_flag after the cbp if cbp luma */
#define CABAC_HDR_DQP_CTX       (1<<13)
#define CABAC_HDR_CCTX_SHIFT    14      /* intra_chroma_pred_mode ctxIdxInc, bits 14-15 */
#define CABAC_HDR_CMODE_SHIFT   16      /* intra_chroma_pred_mode, bits 16-17 */
#define CABAC_HDR_PRED16_SHIFT  18      /* I_16x16 prediction, bits 18-19 */
#define CABAC_HDR_SUB_P         (1<<20) /* sub_mb_type of P_8x8 */
#define CABAC_HDR_SUB_B         (1<<21) /* sub_mb_type of B_8x8 */
#define CABAC_HDR_TCTX_SHIFT    22      /* ctxIdxInc of the first mb_type bin, bits 22-23 */

/* mb_type bin strings (cabac_mbhdr_type in common/x86/cabac-a.asm) */
enum cabac_hdr_type_e
{
    CABAC_HDR_P_16x8 = 0, /* P_L0: + i_partition - D_16x8 */
    CABAC_HDR_P_8x8 = 3,
    CABAC_HDR_P_INXN = 4, /* intra: + 1 for I_16x16 */
    CABAC_HDR_I_INXN = 6,
    CABAC_HDR_B_DIRECT = 8,
    CABAC_HDR_B_8x8 = 9,
    CABAC_HDR_B_INXN = 10,
    CABAC_HDR_B_L0_L0 = 12, /* + (i_mb_type - B_L0_L0) * 3 + i_partition - D_16x8 */
};

typedef struct
{
    uint32_t flags;         /* CABAC_HDR_* */
    int32_t  pos_start;     /* out: x264_cabac_pos before the field flag */
    int32_t  pos_tex;       /* out: x264_cabac_pos after the intra modes or mvd */
    uint8_t  type;          /* cabac_hdr_type_e */
    uint8_t  cbp;           /* luma | chroma << 4 */
    uint8_t  dqp;           /* the 1 bins of mb_qp_delta */
    uint8_t  i_ref;
    uint8_t  i_mvd;
    uint8_t  sub[4];        /* sub_mb_type */
    uint8_t  ref[8];        /* ref_idx in order: scan8 | list << 6 */
    uint8_t  mvd[16];       /* mvd in order: scan8 | list << 6 */
    uint8_t  shape[16];     /* their mvd cache rectangle: width | height << 3, in 4x4 */
    ALIGNED_8( int16_t mvp[16][2] );
} x264_cabac_mbhdr_t;

/* init the contexts given i_slice_type, the quantif and the model */
#define x264_cabac_context_init x264_template(cabac_context_init)
void x264_cabac_context_init( x264_t *h, x264_cabac_t *cb, int i_slice_type, int i_qp, int i_model );

#define x264_cabac_encode_init_core x264_template(cabac_encode_init_core)
void x264_cabac_encode_init_core( x264_cabac_t *cb );
#define x264_cabac_encode_init x264_template(cabac_encode_init)
void x264_cabac_encode_init ( x264_cabac_t *cb, uint8_t *p_data, uint8_t *p_end );
#define x264_cabac_encode_decision_c x264_template(cabac_encode_decision_c)
void x264_cabac_encode_decision_c( x264_cabac_t *cb, int i_ctx, int b );
#define x264_cabac_encode_decision_asm x264_template(cabac_encode_decision_asm)
void x264_cabac_encode_decision_asm( x264_cabac_t *cb, intptr_t i_ctx, intptr_t b );
#define x264_cabac_encode_bypass_c x264_template(cabac_encode_bypass_c)
void x264_cabac_encode_bypass_c( x264_cabac_t *cb, int b );
#define x264_cabac_encode_bypass_asm x264_template(cabac_encode_bypass_asm)
void x264_cabac_encode_bypass_asm( x264_cabac_t *cb, int b );
#define x264_cabac_encode_terminal_c x264_template(cabac_encode_terminal_c)
void x264_cabac_encode_terminal_c( x264_cabac_t *cb );
#define x264_cabac_encode_terminal_asm x264_template(cabac_encode_terminal_asm)
void x264_cabac_encode_terminal_asm( x264_cabac_t *cb );
#define x264_cabac_encode_ue_bypass x264_template(cabac_encode_ue_bypass)
void x264_cabac_encode_ue_bypass( x264_cabac_t *cb, int exp_bits, int val );
#define x264_cabac_encode_flush x264_template(cabac_encode_flush)
void x264_cabac_encode_flush( x264_t *h, x264_cabac_t *cb );

#if HAVE_MMX
#define x264_cabac_encode_decision_bmi2 x264_template(cabac_encode_decision_bmi2)
void x264_cabac_encode_decision_bmi2( x264_cabac_t *cb, intptr_t i_ctx, intptr_t b );
/* the BMI2 version where the CPU has it, set by x264_encoder_open. Both give
 * the same result; the BMI2 one renormalizes with lzcnt/shlx instead of a
 * table load, which sits on the serial range dependency from one bin to the
 * next. A pointer keeps each call site to one well predicted indirect call. */
#define x264_cabac_encode_decision_ptr x264_template(cabac_encode_decision_ptr)
extern void (*x264_cabac_encode_decision_ptr)( x264_cabac_t *cb, intptr_t i_ctx, intptr_t b );
#define x264_cabac_encode_decision x264_cabac_encode_decision_ptr
#define x264_cabac_encode_bypass x264_cabac_encode_bypass_asm
#define x264_cabac_encode_terminal x264_cabac_encode_terminal_asm
#else
#define x264_cabac_encode_decision x264_cabac_encode_decision_c
#define x264_cabac_encode_bypass x264_cabac_encode_bypass_c
#define x264_cabac_encode_terminal x264_cabac_encode_terminal_c
#endif
#define x264_cabac_encode_decision_noup x264_cabac_encode_decision

static ALWAYS_INLINE int x264_cabac_pos( x264_cabac_t *cb )
{
    return (cb->p - cb->p_start + cb->i_bytes_outstanding) * 8 + cb->i_queue;
}

/* internal only. these don't write the bitstream, just calculate bit cost: */

static ALWAYS_INLINE void x264_cabac_size_decision( x264_cabac_t *cb, long i_ctx, long b )
{
    int i_state = cb->state[i_ctx];
    cb->state[i_ctx] = x264_cabac_transition[i_state][b];
    cb->f8_bits_encoded += x264_cabac_entropy[i_state^b];
}

static ALWAYS_INLINE int x264_cabac_size_decision2( uint8_t *state, long b )
{
    int i_state = *state;
    *state = x264_cabac_transition[i_state][b];
    return x264_cabac_entropy[i_state^b];
}

static ALWAYS_INLINE void x264_cabac_size_decision_noup( x264_cabac_t *cb, long i_ctx, long b )
{
    int i_state = cb->state[i_ctx];
    cb->f8_bits_encoded += x264_cabac_entropy[i_state^b];
}

static ALWAYS_INLINE int x264_cabac_size_decision_noup2( uint8_t *state, long b )
{
    return x264_cabac_entropy[*state^b];
}

#endif

/*****************************************************************************
 * crew.h: sliced threads, per-frame input work on every idle thread
 *****************************************************************************
 * Copyright (C) 2026 Open Broadcast Systems Ltd
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
 *****************************************************************************/

#ifndef X264_ENCODER_CREW_H
#define X264_ENCODER_CREW_H

/* With sliced threads the per-frame input work (copy, AQ, lowres, lowres cost)
 * runs as a stage of chunks claimed one at a time by the calling thread, the
 * lookahead pool and the idle slice workers, up to the CPUs available. Each
 * thread runs its chunks on a context of its own (x264_crew_func_t's ctx, a copy
 * of the encoder like lookahead_thread[]). No new threads. */

#define X264_CREW_MAX 32

/* prologue-wide layout set: x264_pw_crew_gate gates the crew (off: the static
 * bands of speed-next), x264_pw_wave_gate the lowres cost wavefront (off: the
 * cost bands on the lookahead pool). On: x264_pw_arm, defined in api.c. Off:
 * the never defined x264_pw_twin, which links as 0. The code is the same.
 * test/x264-prologue-wide: 0 0; -nowave: 0 1; -twin: 1 1. */
#define PW_CREW_TWIN 0
#define PW_WAVE_TWIN 0
extern const char x264_pw_arm __attribute__((weak, visibility("hidden")));
extern const char x264_pw_twin __attribute__((weak, visibility("hidden")));
#if PW_CREW_TWIN
#define x264_pw_crew_gate (&x264_pw_twin != NULL)
#else
#define x264_pw_crew_gate (&x264_pw_arm != NULL)
#endif
#if PW_WAVE_TWIN
#define x264_pw_wave_gate (&x264_pw_twin != NULL)
#else
#define x264_pw_wave_gate (&x264_pw_arm != NULL)
#endif

typedef void (*x264_crew_func_t)( x264_t *ctx, void *arg, int chunk );

/* Run func on chunks [0,chunks) and return once all are done. 0 without a crew. */
#define x264_crew_run x264_template(crew_run)
int  x264_crew_run( x264_t *h, x264_crew_func_t func, void *arg, int chunks );

/* Progress counters between chunks of a stage: a chunk publishes *progress, and
 * one waiting on it sleeps until it reaches need. Returns the value seen. */
#define x264_crew_wait x264_template(crew_wait)
int  x264_crew_wait( x264_t *h, int *progress, int *target, int need );
#define x264_crew_publish x264_template(crew_publish)
void x264_crew_publish( x264_t *h, int *progress, int *target, int value );

/* X264_CREW_ROW ints per MB row, 64-byte aligned, for a stage to use */
#define X264_CREW_ROW 32
#define x264_crew_rows x264_template(crew_rows)
int *x264_crew_rows( x264_t *h );

#endif

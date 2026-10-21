/*****************************************************************************
 * sweep-mbaff-twin.h: layout arm/twin switches of wip/x264-sweep-mbaff (test only)
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

#ifndef X264_X86_SWEEP_MBAFF_TWIN_H
#define X264_X86_SWEEP_MBAFF_TWIN_H

/* 1: dispatch the kernel. 0: dispatch its hidden weak twin, which links as 0, so the slot is
 * NULL and the caller takes the speed-next path. Only these three lines differ between
 * test/x264-sweep-mbaff-{all,dbs,left,border,twin}. */
#define SWEEP_MBAFF_DBS    1
#define SWEEP_MBAFF_LEFT   0
#define SWEEP_MBAFF_BORDER 0

#define SWEEP_TWIN_DECL( fn ) extern __typeof__( fn ) fn##_twin __attribute__((weak, visibility("hidden")));
#define SWEEP_TWIN( on, fn ) ((on) ? fn : fn##_twin)

#endif

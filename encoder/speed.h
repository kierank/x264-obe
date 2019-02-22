#ifndef X264_ENCODER_SPEED_H
#define X264_ENCODER_SPEED_H

#include <stdio.h>
#include <string.h>
#include <math.h>


#define x264_speedcontrol_new x264_template(speedcontrol_new)
void x264_speedcontrol_new( x264_t *h );

#define x264_speedcontrol_delete x264_template(speedcontrol_delete)
void x264_speedcontrol_delete( x264_t *h );

#define x264_speedcontrol_frame_end x264_template(speedcontrol_frame_end)
void x264_speedcontrol_frame_end( x264_t *h );

#define x264_speedcontrol_frame x264_template(speedcontrol_frame)
void x264_speedcontrol_frame( x264_t *h );

#define x264_speedcontrol_sync x264_template(speedcontrol_sync)
void x264_speedcontrol_sync( x264_t *h, float f_buffer_fill, int i_buffer_size, int buffer_complete );

#endif

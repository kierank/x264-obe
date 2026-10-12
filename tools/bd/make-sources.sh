#!/bin/sh
# make-sources.sh <dir>: fetch and prepare 1080i25 BD-rate sources into <dir>
# Native 1080i25 (SVT 2001, LDV mirror at Xiph): parkrun, stockholm, mobcal, shields,
#   8-bit 4:2:0 yuv, 252 frames incl. flat slate frames (dropped here by luma max;
#   parkrun has 5 of them, so it yields 247 frames).
# Woven 1080i25 from the SVT Multi Format 1080p50 masters (Xiph derf): one field
#   per 50p frame, vertically low-passed, as SVT made their 1080i25 versions.
# Outputs per sequence: <name>_1080i25.y4m (8-bit 4:2:0) and
#   <name>_1080i25_422p10.yuv (10-bit 4:2:2 raw), 250 frames, tff.
set -e
D=$1; mkdir -p "$D"; cd "$D"
LDV=https://media.xiph.org/ldv/pub/test_sequences/1080i
DERF=https://media.xiph.org/video/derf/y4m
for s in parkrun stockholm mobcal shields; do
    [ -f 1080i25_${s}_ter.yuv ] || curl -fL -o 1080i25_${s}_ter.yuv $LDV/1080i25_${s}_ter.yuv
    # drop the grey frames: flat mid-grey has YMAX near 128, content has highlights
    ffmpeg -nostdin -loglevel error -f rawvideo -pix_fmt yuv420p -s 1920x1080 -r 25 -i 1080i25_${s}_ter.yuv \
        -vf "signalstats,metadata=mode=select:key=lavfi.signalstats.YMAX:value=160:function=greater,setfield=tff" \
        -frames:v 250 -fps_mode passthrough -y ${s}_1080i25.y4m
done
for s in crowd_run park_joy ducks_take_off in_to_tree old_town_cross; do
    [ -f ${s}_1080p50.y4m ] || curl -fL -o ${s}_1080p50.y4m $DERF/${s}_1080p50.y4m
    ffmpeg -nostdin -loglevel error -i ${s}_1080p50.y4m \
        -vf "tinterlace=mode=interleave_top:flags=vlpf,setfield=tff" -frames:v 250 -y ${s}_1080i25.y4m
done
for f in *_1080i25.y4m; do
    ffmpeg -nostdin -loglevel error -i $f -pix_fmt yuv422p10le -f rawvideo -y ${f%.y4m}_422p10.yuv
done
for f in *_1080i25.y4m; do
    printf '%s frames=%s\n' $f "$(ffprobe -v error -count_frames -select_streams v -show_entries stream=nb_read_frames -of csv=p=0 $f)"
done

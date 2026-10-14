# rack01 scratch: count row VBV re-encodes (x264_ratecontrol_mb < 0 branch) and print "REENC rows N frames F" at encoder close
import sys
R = sys.argv[1].rstrip('/') + '/'; p = R + 'encoder/encoder.c'; s = open(p, encoding='latin-1').read()
a = '        if( x264_ratecontrol_mb( h, mb_size ) < 0 )\n        {\n'
assert s.count(a) == 1
s = s.replace(a, a + '            __atomic_fetch_add( &rack01_reenc_rows, 1, __ATOMIC_RELAXED );\n')
i = s.index('#include "common/common.h"\n') + len('#include "common/common.h"\n')
s = s[:i] + 'static int rack01_reenc_rows;\n' + s[i:]
d = 'void    x264_encoder_close  ( x264_t *h )\n{\n'
assert s.count(d) == 1
s = s.replace(d, d + '    fprintf( stderr, "REENC rows %d\\n", rack01_reenc_rows );\n')
open(p, 'w', encoding='latin-1').write(s); print('ok', R)

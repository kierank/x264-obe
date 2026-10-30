/* Synthetic 10-bit 4:2:2 tff y4m: fine-detail "city" texture, slow subpixel pan,
 * field-temporal sampling, gaussian sensor noise.
 * gen W H frames dx dy noise_sigma10 seed [kind] > out.y4m
 * kind 0 = city (stockholm-like), 1 = calendar (mobcal-like: grid of digits + moving object) */
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <math.h>
#include <string.h>

static uint64_t rs;
static inline uint64_t rnd( void ) { rs ^= rs << 13; rs ^= rs >> 7; rs ^= rs << 17; return rs; }
static inline double urnd( void ) { return (rnd() >> 11) * (1.0 / 9007199254740992.0); }
static double grnd( void ) { double u = urnd() + 1e-12, v = urnd(); return sqrt( -2 * log( u ) ) * cos( 6.283185307 * v ); }

static inline float X264_MIN_F( float a ) { return a > 0.98f ? 0.98f : a; }
static int TW, TH; /* texture at 2x output scale */
static float *tex;

static float *vnoise_lat;
static float vnoise( double x, double y, int cell, int lw )
{
    double fx = x / cell, fy = y / cell;
    int ix = (int)fx, iy = (int)fy;
    double tx = fx - ix, ty = fy - iy;
    tx = tx * tx * (3 - 2 * tx); ty = ty * ty * (3 - 2 * ty);
#define L(a,b) vnoise_lat[((b) % lw) * lw + ((a) % lw)]
    double a = L(ix,iy) + (L(ix+1,iy) - L(ix,iy)) * tx;
    double b = L(ix,iy+1) + (L(ix+1,iy+1) - L(ix,iy+1)) * tx;
    return a + (b - a) * ty;
}

static void build_city( void )
{
    int lw = 4096;
    vnoise_lat = malloc( sizeof(float) * lw * lw );
    for( int i = 0; i < lw * lw; i++ ) vnoise_lat[i] = urnd();
    for( int y = 0; y < TH; y++ )
        for( int x = 0; x < TW; x++ )
        {
            double v = 0, amp = 0.5;
            for( int c = 512; c >= 2; c >>= 1, amp *= 0.62 )
                v += amp * (vnoise( x + c * 7.3, y + c * 3.1, c, lw ) - 0.5);
            tex[y * TW + x] = 0.45 + 0.5 * v;
        }
    /* buildings: rectangles with window grids */
    for( int k = 0; k < 900; k++ )
    {
        int w = 40 + rnd() % 400, h = 60 + rnd() % 600;
        int x0 = rnd() % TW, y0 = rnd() % TH;
        float base = 0.15 + 0.7 * urnd();
        int px = 6 + rnd() % 14, py = 8 + rnd() % 18;
        int wx = 2 + rnd() % (px - 3), wy = 2 + rnd() % (py - 3);
        float win = urnd() < 0.5 ? base * 0.35 : X264_MIN_F( base * 1.6 + 0.1 );
        for( int y = y0; y < y0 + h && y < TH; y++ )
            for( int x = x0; x < x0 + w && x < TW; x++ )
            {
                float t = tex[y * TW + x];
                float v = base + 0.25 * (t - 0.45);
                if( (x - x0) % px < wx && (y - y0) % py < wy ) v = win + 0.1 * (t - 0.45);
                if( (x - x0) < 2 || (y - y0) < 2 ) v = base * 0.6;
                tex[y * TW + x] = v;
            }
    }
}

static void build_calendar( void )
{
    int lw = 4096;
    vnoise_lat = malloc( sizeof(float) * lw * lw );
    for( int i = 0; i < lw * lw; i++ ) vnoise_lat[i] = urnd();
    for( int y = 0; y < TH; y++ )
        for( int x = 0; x < TW; x++ )
        {
            double v = 0, amp = 0.5;
            for( int c = 64; c >= 2; c >>= 1, amp *= 0.7 )
                v += amp * (vnoise( x + c * 5.3, y + c * 9.1, c, lw ) - 0.5);
            /* wallpaper stripes and dots */
            double s = 0.5 + 0.5 * sin( x * 0.9 + 0.3 * sin( y * 0.05 ) );
            tex[y * TW + x] = 0.55 + 0.15 * s + 0.35 * v;
        }
    /* calendar cells with 5x7 glyphs */
    int cw = 120, ch = 100;
    for( int cy = 0; cy + ch < TH; cy += ch + 6 )
        for( int cx = 0; cx + cw < TW; cx += cw + 6 )
        {
            float bg = 0.85 + 0.1 * urnd();
            for( int y = cy; y < cy + ch; y++ )
                for( int x = cx; x < cx + cw; x++ )
                    tex[y * TW + x] = bg + 0.05 * (tex[y * TW + x] - 0.55);
            for( int g = 0; g < 2; g++ )
            {
                uint64_t pat = rnd();
                int gx = cx + 20 + g * 40, gy = cy + 20, sc = 6;
                for( int j = 0; j < 7; j++ )
                    for( int i = 0; i < 5; i++ )
                        if( (pat >> (j * 5 + i)) & 1 )
                            for( int yy = 0; yy < sc; yy++ )
                                for( int xx = 0; xx < sc; xx++ )
                                    tex[(gy + j * sc + yy) * TW + gx + i * sc + xx] = 0.08;
            }
        }
}



static inline double samp( double x, double y )
{
    /* box over the 2x2 texels of one output pixel: bilinear at the centre of a 2x2 footprint */
    x *= 2; y *= 2;
    if( x < 0 ) x = 0;
    if( y < 0 ) y = 0;
    if( x > TW - 3 ) x = TW - 3;
    if( y > TH - 3 ) y = TH - 3;
    int ix = (int)x, iy = (int)y;
    double fx = x - ix, fy = y - iy;
    double acc = 0;
    for( int j = 0; j < 2; j++ )
        for( int i = 0; i < 2; i++ )
        {
            int xx = ix + i, yy = iy + j;
            float *t = &tex[yy * TW + xx];
            double a = t[0] + (t[1] - t[0]) * fx;
            double b = t[TW] + (t[TW + 1] - t[TW]) * fx;
            acc += a + (b - a) * fy;
        }
    return acc * 0.25;
}

int main( int argc, char **argv )
{
    if( argc < 8 ) { fprintf( stderr, "gen W H frames dx dy sigma10 seed [kind]\n" ); return 1; }
    int W = atoi( argv[1] ), H = atoi( argv[2] ), N = atoi( argv[3] );
    double dx = atof( argv[4] ), dy = atof( argv[5] ), sig = atof( argv[6] );
    rs = 0x9E3779B97F4A7C15ull ^ (uint64_t)atoi( argv[7] ) * 0x2545F4914F6CDD1Dull;
    int kind = argc > 8 ? atoi( argv[8] ) : 0;
    TW = 2 * (W + (int)(fabs( dx ) * N) + 64);
    TH = 2 * (H + (int)(fabs( dy ) * N) + 64);
    tex = malloc( sizeof(float) * TW * TH );
    if( kind == 1 ) build_calendar(); else build_city();
    printf( "YUV4MPEG2 W%d H%d F25:1 It A1:1 C422p10 XYSCSS=422P10\n", W, H );
    uint16_t *y = malloc( W * H * 2 ), *u = malloc( W * H ), *v = malloc( W * H );
    double ox0 = dx < 0 ? fabs( dx ) * N + 16 : 16, oy0 = dy < 0 ? fabs( dy ) * N + 16 : 16;
    for( int f = 0; f < N; f++ )
    {
        for( int r = 0; r < H; r++ )
        {
            double t = f + 0.5 * (r & 1); /* tff: bottom field half a frame later */
            double ox = ox0 + dx * t, oy = oy0 + dy * t;
            /* moving object (train) for calendar */
            for( int c = 0; c < W; c++ )
            {
                double val = samp( ox + c, oy + r );
                if( kind == 1 )
                {
                    double tx = 200 + 4.0 * t, tyy = H * 0.7;
                    if( c > tx && c < tx + 500 && r > tyy && r < tyy + 120 )
                        val = 0.3 + 0.2 * samp( c - tx + 3000, r + 500 );
                }
                double p = 64 + 876 * val + sig * grnd();
                int q = (int)floor( p + 0.5 );
                y[r * W + c] = q < 4 ? 4 : q > 1019 ? 1019 : q;
            }
            for( int c = 0; c < W / 2; c++ )
            {
                double cu = 512 + 60 * (samp( ox + 2 * c + 500, oy + r + 300 ) - 0.5) + 0.5 * sig * grnd();
                double cv = 512 + 60 * (samp( ox + 2 * c + 900, oy + r + 100 ) - 0.5) + 0.5 * sig * grnd();
                u[r * W / 2 + c] = (int)(cu + 0.5);
                v[r * W / 2 + c] = (int)(cv + 0.5);
            }
        }
        printf( "FRAME\n" );
        fwrite( y, 2, W * H, stdout );
        fwrite( u, 2, W * H / 2, stdout );
        fwrite( v, 2, W * H / 2, stdout );
    }
    return 0;
}

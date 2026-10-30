/* an dump.bin : summarise LA8SHADOW per-MB records (d=0 full depth, d=1 8-bit) */
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <math.h>

typedef struct { int32_t frame, p0, p1, b, mb; int32_t c[2], lu[2], ic[2]; } rec_t;

#define NB 12
typedef struct { double n, s0, s1, s00, s11, s01; double bn[NB], b0[NB], b1[NB]; double lu[4][4]; } acc_t;

static void add( acc_t *a, double x0, double x1, int l0, int l1 )
{
    a->n++; a->s0 += x0; a->s1 += x1; a->s00 += x0 * x0; a->s11 += x1 * x1; a->s01 += x0 * x1;
    int bin = 0;
    while( bin < NB - 1 && x0 >= (8 << bin) ) bin++;
    a->bn[bin]++; a->b0[bin] += x0; a->b1[bin] += x1;
    a->lu[l0 & 3][l1 & 3]++;
}

static void pr( const char *name, acc_t *a, int showlu )
{
    if( !a->n ) return;
    double m0 = a->s0 / a->n, m1 = a->s1 / a->n;
    double v0 = a->s00 / a->n - m0 * m0, v1 = a->s11 / a->n - m1 * m1, cv = a->s01 / a->n - m0 * m1;
    printf( "%-6s n=%8.0f mean10=%8.2f mean8=%8.2f ratio=%.4f diff=%+7.2f corr=%.4f\n", name, a->n, m0, m1, m1 / m0, m1 - m0,
            cv / sqrt( v0 * v1 ) );
    printf( "       bins(c10<):" );
    for( int i = 0; i < NB; i++ )
        if( a->bn[i] )
            printf( " [%d: n=%.0f %+.1f %.3f]", 8 << i, a->bn[i], (a->b1[i] - a->b0[i]) / a->bn[i], a->b1[i] / a->b0[i] );
    printf( "\n" );
    if( showlu )
    {
        printf( "       list_used 10->8 (rows 10-bit, cols 8-bit; 0 intra 1 L0 2 L1 3 bi):\n" );
        for( int i = 0; i < 4; i++ )
            printf( "         %d: %8.0f %8.0f %8.0f %8.0f\n", i, a->lu[i][0], a->lu[i][1], a->lu[i][2], a->lu[i][3] );
    }
}

int main( int argc, char **argv )
{
    FILE *f = fopen( argv[1], "rb" );
    if( !f ) return 1;
    int maxdist = argc > 2 ? atoi( argv[2] ) : 99;
    static acc_t I, P1, Pn, B, Bl[4], IC;
    rec_t r;
    while( fread( &r, sizeof(r), 1, f ) == 1 )
    {
        int bp0 = r.b & 15, p1b = r.b >> 4;
        if( bp0 + p1b > maxdist ) continue;
        if( !bp0 && !p1b )
        {
            add( &I, r.c[0], r.c[1], 0, 0 );
            continue;
        }
        if( !p1b )
            add( bp0 == 1 ? &P1 : &Pn, r.c[0], r.c[1], r.lu[0], r.lu[1] );
        else
        {
            add( &B, r.c[0], r.c[1], r.lu[0], r.lu[1] );
            if( r.lu[0] == r.lu[1] )
                add( &Bl[r.lu[0] & 3], r.c[0], r.c[1], r.lu[0], r.lu[1] );
        }
    }
    pr( "I", &I, 0 );
    pr( "P1", &P1, 1 );
    pr( "Pn", &Pn, 1 );
    pr( "B", &B, 1 );
    pr( "B-L0", &Bl[1], 0 );
    pr( "B-L1", &Bl[2], 0 );
    pr( "B-bi", &Bl[3], 0 );
    double rp = (P1.s1 + Pn.s1) / (P1.s0 + Pn.s0), rb = B.s1 / B.s0, ri = I.s1 / I.s0;
    printf( "SUMMARY ratio8/10: I %.4f P %.4f B %.4f  B/P %+.2f%%  B/I %+.2f%%  P/I %+.2f%%\n", ri, rp, rb,
            100 * (rb / rp - 1), 100 * (rb / ri - 1), 100 * (rp / ri - 1) );
    return 0;
}

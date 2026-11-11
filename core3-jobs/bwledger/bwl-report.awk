# Copyright (C) 2026 Open Broadcast Systems Ltd
# Ledger log (x264 built with -DX264_BWLEDGER=1, stderr) -> MB per frame tables.
#   awk -f bwl-report.awk [-v table=frames] ledger.log
# Default: totals mapped onto the rows of the membw audit's cell tables, plus touched
# fractions per reference plane. table=frames: one TSV row per encoded frame.
# MB = 1e6 bytes. Writes are bytes stored; the audit's RFO (write-allocate read) is
# not a ledger quantity: plain-store streams cost about 2x their bytes, NT streams
# (hpel, field hpel copy) 1x.
function mb( b ) { return sprintf( "%7.3f", b / F / 1e6 ) }
function isref( c ) { return c ~ /^(F|H|V|C|Ffld|Hfld|Vfld|Cfld)$/ }
function islr( c ) { return c ~ /^lr[0-3]$/ }
function issrc( c ) { return c ~ /^(src_y|src_c|ext)$/ }
$1 == "BWLT"  { F = $2; rd[$3" "$4] += $5; wr[$3" "$4] += $6; st[$3] = 1; cl[$4] = 1 }
$1 == "BWLTU" { F = $2; u[$3" "$4] += $5 }
$1 == "BWLROW" { row = $2; rframe[row] = $3; rtype[row] = $4; nrow = row + 1 }
$1 == "BWLS" {
    s = $3; c = $4; r = $5; w = $6; n = $2
    if( (s == "aq" || s == "lowres") && issrc( c ) ) fr[n, "prolog"] += r
    if( s == "lowres" && islr( c ) ) fr[n, "lowres"] += w
    if( s == "srcpad" ) fr[n, "srcpad"] += w
    if( s == "latree" || (s == "la" && c == "arr_la") ) fr[n, "latree"] += r + w
    if( s == "srcenc" ) fr[n, "srcenc"] += r
    if( s == "fdec" ) fr[n, "fdec"] += w
    if( s == "mbarr" ) fr[n, "mbarr"] += r + w
    if( s == "hpel" || s == "fldcopy" ) fr[n, "hpel"] += w
    if( s == "border" ) fr[n, "border"] += w
    if( s == "weight" ) fr[n, "weight"] += r + w
    if( s == "bs" ) fr[n, "bs"] += w
}
$1 == "BWLU" {
    n = $2; g = $3; c = $4
    if( g == "LA" ) fr[n, "la_u"] += $6
    if( g == "EN" && isref( c ) ) { fr[n, "ref_u"] += $6; fu[c] += $6; fi[c] += $7; fn[c]++; if( $6 / $7 > fmax[c] ) fmax[c] = $6 / $7 }
    if( g == "EN" && c ~ /^uv/ ) { fr[n, "uv_u"] += $6; fu[c] += $6; fi[c] += $7; fn[c]++; if( $6 / $7 > fmax[c] ) fmax[c] = $6 / $7 }
    if( g == "EN" && c == "wbuf" ) fr[n, "wbuf_u"] += $6
    if( g == "LA" && islr( c ) ) { fu[c] += $6; fi[c] += $7; fn[c]++; if( $6 / $7 > fmax[c] ) fmax[c] = $6 / $7 }
    if( g == "EN" && c == "F" ) nref[n]++
}
END {
    if( table == "frames" )
    {
        printf "row\tframe\ttype\tprolog\tsrcpad\tlowres\tla_u\tlatree\tsrcenc\tref_u\tuv_u\twbuf_u\tweight\tfdec\tmbarr\thpel\tborder\tbs\ttotal\trefs\n"
        split( "prolog srcpad lowres la_u latree srcenc ref_u uv_u wbuf_u weight fdec mbarr hpel border bs", k, " " )
        for( n = 0; n < nrow; n++ )
        {
            t = 0
            printf "%d\t%d\t%s", n, rframe[n], rtype[n]
            for( i = 1; i in k; i++ ) { printf "\t%.3f", fr[n, k[i]] / 1e6; t += fr[n, k[i]] }
            printf "\t%.3f\t%d\n", t / 1e6, nref[n]
        }
        exit
    }
    if( !F ) { print "no BWLT totals (not a ledger build, or the encode failed)"; exit 1 }
    for( k2 in rd ) { split( k2, a, " " ); s = a[1]; c = a[2]
        if( (s == "aq" || s == "lowres") && issrc( c ) ) prolog += rd[k2]
        if( s == "srcpad" ) srcpad += wr[k2]
        if( s == "lowres" && islr( c ) ) lowres += wr[k2]
        if( s == "aq" && c == "arr_rc" ) aqarr += wr[k2]
        if( (s == "la" || s == "laintra") && islr( c ) ) lareq += rd[k2]
        if( s == "latree" ) tree += rd[k2] + wr[k2]
        if( s == "la" && c == "arr_la" ) laarr += rd[k2] + wr[k2]
        if( s == "srcenc" ) srcenc += rd[k2]
        if( (s == "me" || s == "mc") && isref( c ) ) refreq += rd[k2]
        if( (s == "me" || s == "mc") && c ~ /^uv/ ) uvreq += rd[k2]
        if( s == "weight" ) weight += rd[k2] + wr[k2]
        if( s == "fdec" ) fdec += wr[k2]
        if( s == "mbarr" ) { mbrd += rd[k2]; mbwr += wr[k2] }
        if( s == "hpel" ) { hpelw += wr[k2]; hpelr += rd[k2] }
        if( s == "fldcopy" ) fldw += wr[k2]
        if( s == "border" ) border += wr[k2]
        if( s == "deblock" ) deb += rd[k2] + wr[k2]
        if( s == "bs" ) bs += wr[k2]
        if( s == "srccopy" ) cli += rd[k2] + wr[k2]
    }
    for( k2 in u ) { split( k2, a, " " ); g = a[1]; c = a[2]
        if( g == "LA" && islr( c ) ) lau += u[k2]
        if( g == "EN" && isref( c ) ) refu += u[k2]
        if( g == "ME" && isref( c ) ) refme += u[k2]
        if( g == "MC" && isref( c ) ) refmc += u[k2]
        if( g == "EN" && c ~ /^uv/ ) uvu += u[k2]
        if( g == "EN" && c == "wbuf" ) wbufu += u[k2]
    }
    printf "frames %d; MB per frame (1e6 B); writes are bytes stored (no RFO)\n", F
    printf "%-62s %s\n", "stage (audit cell-table row)", "MB/f"
    printf "%-62s %s\n", "source read, prologue (AQ + lowres)", mb( prolog )
    printf "%-62s %s   (lines dirtied x 64)\n", "writes into the source plane (mod16 pad, lowres edge)", mb( srcpad )
    printf "%-62s %s\n", "lowres 4 planes + pads, written", mb( lowres )
    printf "%-62s %s\n", "AQ / qp arrays, written", mb( aqarr )
    printf "%-62s %s   (requested %s)\n", "lookahead ME + intra: distinct lowres lines per row", mb( lau ), mb( lareq )
    printf "%-62s %s   (+ lowres per-MB arrays %s)\n", "mbtree propagate / finish arrays", mb( tree ), mb( laarr )
    printf "%-62s %s\n", "source re-read by the encode (fenc MB loads)", mb( srcenc )
    printf "%-62s %s   (ME %s, MC %s, requested %s)\n", "ME/MC luma refs: distinct lines per consumer frame", mb( refu ), mb( refme ), mb( refmc ), mb( refreq )
    printf "%-62s %s   (requested %s)\n", "chroma MC: distinct lines per consumer frame", mb( uvu ), mb( uvreq )
    printf "%-62s %s   (weight-buffer lines read %s)\n", "weighted ref planes, built (read + write)", mb( weight ), mb( wbufu )
    printf "%-62s %s\n", "fdec recon, written", mb( fdec )
    printf "%-62s %s   (read %s, written %s; reads estimated)\n", "per-MB arrays", mb( mbrd + mbwr ), mb( mbrd ), mb( mbwr )
    printf "%-62s %s   (field hpel copy %s; F read %s, L2-hot)\n", "hpel H/V/C (frame + field), written", mb( hpelw ), mb( fldw ), mb( hpelr )
    printf "%-62s %s\n", "borders of fdec planes, written", mb( border )
    printf "%-62s %s   (in place, one row behind the encode)\n", "deblock read + write", mb( deb )
    printf "%-62s %s\n", "bitstream + NAL escape, written", mb( bs )
    printf "%-62s %s   (CLI only; encode_ext borrows)\n", "CLI picture copy", mb( cli )
    tot = prolog + srcpad + lowres + aqarr + lau + tree + laarr + srcenc + refu + uvu + weight + wbufu + fdec + mbrd + mbwr + hpelw + fldw + border + bs
    rfo = srcpad + lowres + fdec + border + aqarr + mbwr
    printf "%-62s %s   (+ RFO of plain-store writes %s = %s)\n", "TOTAL, audit-comparable (distinct lines for reads)", mb( tot ), mb( rfo ), mb( tot + rfo )
    print ""
    print "touched fraction per plane: distinct lines read / interior bytes, mean over (row, plane), max"
    for( c in fu ) printf "  %-6s mean %.3f  max %.3f  (%d row-planes)\n", c, fu[c] / fi[c], fmax[c], fn[c]
}

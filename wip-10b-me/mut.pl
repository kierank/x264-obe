# usage: perl mut.pl <file> <find> <replace>: replaces the first literal <find> after the MH marker
# (a backslash-n in either is a newline); exit 1 if none
my ($f, $a, $b) = @ARGV;
my $nl = chr(92) . 'n';
$a = join( "\n", split( /\Q$nl\E/, $a, -1 ) );
$b = join( "\n", split( /\Q$nl\E/, $b, -1 ) );
local $/; open my $h, '<', $f or die; my $s = <$h>; close $h;
my $m = index( $s, "me_search_fpel_inline avx512, high bit depth" ); die "no marker" if $m < 0;
my $i = index( $s, $a, $m ); exit 1 if $i < 0;
substr( $s, $i, length $a ) = $b;
open $h, '>', $f or die; print $h $s; close $h;

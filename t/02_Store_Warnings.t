#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use Capture::Tiny ':all';
use Game::MarbleRun::Store;

Game::MarbleRun::loc_lang('C');

# create and populate database
my $g = Game::MarbleRun::Store->new(db => ':memory:');
# reply with yes to all questions
$g->{answer} = 'Y';

# Store.pm line 155
my $run = [['name', 'a test'],['A', 3, 4, 5, '', 2, 0, [5, 5, 's', 2, '']]];
like(capture_stderr{$g->store_run($run)}, qr/no tile at/i, 'no tile');

# Store.pm line 86
push @$run, ['C', 5, 5, 3, '', 5 ,0];
push @$run, ['C', 5, 5, 3, '', 5 ,0];
like(capture_stderr{$g->store_run($run)}, qr/already a/i, 'duplicate tile');
pop @$run;

# Store.pm line 109
# following checks only succeed if no previous errors
$g->{warn} = 0;
push @$run, ['C', 6, 5, 7, '', 5, 0 , [6, 5, 't', 0, '']];
like(capture_merged{$g->store_run($run)}, qr/end point/i, 'vertical rail');
pop @$run;
# rail data still get mangled
$run = [['name', 'a test'],['A', 3, 4, 5, '', 2, 0, [5, 5, 's', 2, '']]];

# Store.pm line 379
$g->{warn} = 0;
push @$run, ['C', 5, 5, 3, '', 5, 0, [3, 4, 's', 5, '']];
like(capture_merged{$g->store_run($run)}, qr/already/s, 'duplicate rail');
pop @$run;

# Store.pm line 124
$run = [['name', 'another test'],['A', 3, 4, 5, '', 2, 0, [5, 5, 's', 2]]];
push @$run, ['C', 5, 5, 3, '', 5, 0];
$g->{warn} = 0;
$run->[-1][5] = 2;
like(capture_stderr{$g->store_run($run)}, qr/no connection from/i, 'to tile');

$g->{warn} = 0;
$run->[-1][5] = 1;
push @$run, ['L', 1, 1, 0, '', 3, 0, [3, 3, 'xs', 3, 22]];
$run->[0] = ['name', 'pillar'];
like(capture_merged{$g->store_run($run)}, qr/No pillar/, 'No pillar');

# Store.pm line 149
$g->{warn} = 0;
$run->[-1][5] = 5;
$run->[1][5] = 1;
like(capture_stderr{$g->store_run($run)}, qr/no connection from/i, 'from tile');

# Store.pm line 386
$g->{warn} = 0;
$run = [['name', 'basic_a']];
like(capture_stderr{$g->store_run($run)}, qr/no valid data/i, 'no data');

$g->{check_only} = 0;
### parse line checks: errors ###
my $line = [
	# errors in store_run
	'no pillar' => ['33 L;33 xld' => qr/pillar for end of wall/i, 'run'], # 67
	'outside of board' => ['11 Ca la' => qr/outside of board/i, 'run'], # 173
	'already a tile' => ['11 Ca;11 Ca' => qr/already a tile/i, 'run'], # 196
	'no connection tile' => ['11 Ca sd;31 Cb' => qr/from tile/i, 'run'], # 263
	'no connection rail' => ['11 Ca sd;31 Cb' => qr/from rail/i, 'run'], # 311
	'no tile at' => ['11 Ca xtd' => qr/no tile at/i, 'run'], # 317
	'duplicate rail' => ['11 Cd sd;31 Ca sa' => qr/registered/i, 'run'], # 583
	'no end point' => ['11 Cd sd' => qr/no end point/i, 'run'], # 590
	'no valid data' => ['' => qr/no valid data/i, 'run'], # 598
	# header line
	'name and semicolon' => ['test;33 Ca' => qr//i, 'run'], # 812
	'name redefinition' => ['name a' => qr/redefinition of run/i, 'run'], # 812
	'no name in first line' => ['name' => qr/missing run name/i, 'run'], # 813
	'no level number' => ['level' => qr/level number not given/i, 'run'], # 820
	'wrong level' => ['level a' => qr/wrong level/i, 'run'], # 832
	'repeated level' => ['level 1;level 1' => qr/already seen/i, 'run'], # 839
	# tile definition
	'wrong position' => ['abc' => qr/wrong tile position/i, 'run'], # 630
	'position unknown' => ['level 1;^' => qr/position unknown/i, 'run'], # 711
	'wrong ground plane number' => ['_ 7 a' => qr/ground plane/, 'run'], # 857
	'wrong omitted ground plane' => ['! 7 a' => qr/ground plane/, 'run'], # 864
	'no further data' => ['22' => qr/further data/i, 'run'], # 878
	'wrong position' => ['11 ^;55 L' => qr/wrong tile position/i, 'run'], # 911
	'double balcony' => ['11 Ea Ca' => qr/first position/i, 'run'], # 938
	'double balcony dir' => ['33 1Ea;23 Eb' => qr/wrong dir/i, 'run'], # 950
	'balcony height' => ['22 xlb;33 eBa' => qr/wrong balcony/i, 'run'], # 965
	'balcony' => ['33 1Ba' => qr/not yet seen/i, 'run'], # 970
	'balcony dir' => ['22 xlb;33 eBa' => qr/wrong direction/i, 'run'], # 980
	'tunnel pillar' => ['22 xL' => qr/direction missing/i, 'run'], # 1002
	'helix elements' => ['22 xH1a'=> qr/helix/i, 'run'], # 1041
	'bridge elements' => ['41 xB9d' => qr/even number/i, 'run'], # 1046
	'mixer' => ['41 xMab' => qr/mixer orientation/i, 'run'], # 1064
	'open basket' => ['22 3Oa' => qr/no height/si, 'run'], # 1067
	'excess tile char' => ['22 Caa' => qr/excess/i, 'run'], # 1080
	'wrong orientation' => ['22 Cx' => qr/wrong orient/i, 'run'], # 1083
	'rail instead of tile' => ['22 sa' => qr/not a tile/i, 'run'], # 1088
	'missing orientation' => ['22 C' => qr/missing tile orient/i, 'run'], # 1090
	'no orientation' => ['22 Oa' => qr/no orientation/si, 'run'], # 1092
	'wrong tile char' => ['22 %' => qr/wrong tile char/i, 'run'], # 1095
	#'no tile data' => ['22 3 y' => qr/no tile data/i, 'run'], # 1097
	'unexpected data' => ['44 ^ Ca sa' => qr/unexpected data/i, 'run'], # 1111
	# rail data
	'wrong rail char' => ['22 Ca La' => qr/wrong rail char/i, 'run'], # 1125
	'flextube' => ['22 Ca xta' => qr/two directions/i, 'run'], # 1131
	'duplicate rail' => ['42 Ca sd sd' => qr/same direction/i, 'run'], # 1145
	'wrong direction' => ['22 Ca sx' => qr/wrong rail dir/i, 'run'], # 1154
	'missing direction' => ['22 Ca s' => qr/missing rail dir/i, 'run'], # 1156
	'excess rail char' => ['33 Ca sad' => qr/excess/i, 'run'], # 1159
	'wrong rail data' => ['33 Ca yy' => qr/rail data/i, 'run'], # 1163
	'max 3 rails' => ['44 Ca sa sb sc sd se' => qr/maximum/i, 'run'], # 1173
	# marble data
	'wrong tile for marble' => ['33 Ca oSa' => qr/placed on/i, 'run'], # 1216
	'wrong char for marble' => ['33 Aa oFa' => qr/illegal/i, 'run'], # 1228
	'marble' => ['33 Aa oRb' => qr/in position/i, 'run'], # 1239
	'wrong marble pos' => ['33 Aa ob' => qr/in position/i, 'run'], # 1255
	# material input
	'wrong element char' => ['1 %' => qr/unknown element/i, 'mat'], # 1306
	'ambig set' => ['1 Tr' => qr/ambig set/i, 'mat'], # 1330
	'unknown set' => ['1 Tux' => qr/unknown set/i, 'mat'], # 1334
	'unknown line' => ['bla' => qr/unknown material/i, 'mat'], # 1337
];
while (my($s, $l) = splice(@$line, 0, 2)) {
	$g->{warn} = 0;
	my $content = "test\n$l->[0]";
	if ($l->[2] eq 'run') {
		like(capture_stderr{{my $rules=$g->parse_run($content);
								$g->store_run($rules)}}, $l->[1], $s);
	} else {
		like(capture_stderr{$g->parse_material($content)}, $l->[1], $s);
	}
}

done_testing();

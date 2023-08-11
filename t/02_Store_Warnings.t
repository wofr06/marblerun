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

$g->{check_only} = 0;
### parse line checks: errors ###
my $line = [
	# errors in parse_run, store_run and helper functions
	# errors in store_run
	'outside' => ['11 Aa sa' => qr/outside of board/i, 'run'], # 75
	'already a tile' => ['11 Ca;11 Ca' => qr/already a tile/i, 'run'], # 96
	'tile at finish line' => ['11 Ce ec;12 Ce' => qr/tile at end/i, 'run'],# 118
	'tile to rail' => ['11 Ca sd;31 Ca' => qr/between tile/i, 'run'], # 164
	'rail to tile' => ['11 Cd sd;31 Cb' => qr/to a tile from/i, 'run'], # 169
	'duplicate rail' => ['11 Cd sd;31 Ca sa' => qr/registered/i, 'run'], # 517
	'no valid data' => ['' => qr/no valid data/i, 'run'], # 534
	'wrong position' => ['11 ^;55 L' => qr/wrong tile position/i, 'run'], # 566
	'position unknown' => ['level 1;^' => qr/position unknown/i, 'run'], # 645
	# header line
	'name and semicolon' => ['test;33 Ca' => qr//i, 'run'], # 745
	'name redefinition' => ['name a' => qr/redefinition of run/i, 'run'], # 745
	'no name in first line' => ['name' => qr/missing run name/i, 'run'], # 746
	'no level number' => ['level' => qr/level number not given/i, 'run'], # 756
	'wrong level' => ['level a' => qr/wrong level/i, 'run'], # 765
	'repeated level' => ['level 1;level 1' => qr/already seen/i, 'run'], # 772
	# tile definition
	'wrong ground plane number' => ['_ 7 a' => qr/ground plane/, 'run'], # 790
	'wrong omitted ground plane' => ['! 7 a' => qr/ground plane/, 'run'], # 797
	'no further data' => ['22' => qr/further data/i, 'run'], # 808
	'wrong position2' => ['abc' => qr/wrong tile position/i, 'run'], # 840
	'double balcony' => ['11 Ea Ca' => qr/first position/i, 'run'], # 865
	'double balcony dir' => ['33 1Ea;23 Eb' => qr/wrong dir/i, 'run'], # 877
	'balcony height' => ['22 xlb;33 eBa' => qr/wrong balcony/i, 'run'], # 891
	'balcony' => ['33 1Ba' => qr/not yet seen/i, 'run'], # 896
	'balcony dir' => ['22 xlb;33 eBa' => qr/wrong direction/i, 'run'], # 906
	'tunnel pillar' => ['22 xL' => qr/direction missing/i, 'run'], # 926
	'helix elements' => ['22 xH1a'=> qr/helix/i, 'run'], # 965
	'bridge elements' => ['41 xB9d' => qr/even number/i, 'run'], # 970
	'mixer' => ['41 xMaa' => qr/mixer orientation/i, 'run'], # 988
	'open basket' => ['22 3Oa' => qr/no height/si, 'run'], # 991
	'excess tile char' => ['22 Caa' => qr/excess/i, 'run'], # 1004
	'wrong orientation' => ['22 Cx' => qr/wrong orient/i, 'run'], # 1007
	'rail instead of tile' => ['22 sa' => qr/not a tile/i, 'run'], # 1012
	'missing orientation' => ['22 C' => qr/missing tile orient/i, 'run'], # 1014
	'no orientation' => ['22 Oa' => qr/no orientation/si, 'run'], # 1016
	'wrong tile char' => ['22 %' => qr/wrong tile char/i, 'run'], # 1019
	#'no tile data' => ['22 3 y' => qr/no tile data/i, 'run'], # 1022
	'unexpected data' => ['44 ^ Ca sa' => qr/unexpected data/i, 'run'], # 1036
	# rail data
	'wrong rail char' => ['22 Ca La' => qr/wrong rail char/i, 'run'], # 1049
	'flextube' => ['22 Ca xta' => qr/two directions/i, 'run'], # 1054
	'duplicate rail' => ['42 Ca sd sd' => qr/same direction/i, 'run'], # 1069
	'wrong direction' => ['22 Ca sx' => qr/wrong rail dir/i, 'run'], # 1078
	'missing direction' => ['22 Ca s' => qr/missing rail dir/i, 'run'], # 1080
	'excess rail char' => ['33 Ca sad' => qr/excess/i, 'run'], # 1083
	'wrong rail data' => ['33 Ca yy' => qr/rail data/i, 'run'], # 1087
	'max 3 rails' => ['44 Ca sa sb sc sd se' => qr/maximum/i, 'run'], # 1097
	# marble data
	'wrong tile for marble' => ['33 Ca oSa' => qr/placed on/i, 'run'], # 1138
	'wrong char for marble' => ['33 Aa oFa' => qr/illegal/i, 'run'], # 1151
	'marble' => ['33 Aa oRb' => qr/in position/i, 'run'], # 1164
	'wrong marble pos' => ['33 Aa ob' => qr/in position/i, 'run'], # 1179
	# material input
	'wrong element char' => ['1 %' => qr/unknown element/i, 'mat'], # 1230
	'ambig set' => ['1 Tr' => qr/ambig set/i, 'mat'], # 1254
	'unknown set' => ['1 Tux' => qr/unknown set/i, 'mat'], # 1258
	'unknown line' => ['bla' => qr/unknown material/i, 'mat'], # 1261
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

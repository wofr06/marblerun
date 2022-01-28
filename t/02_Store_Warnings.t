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
push @$run, ['C', 6, 5, 3, '', 5, 0 , [6, 5, 't', 0, '']];
like(capture_merged{$g->store_run($run)}, qr/end point/i, 'vertical rail');
pop @$run;
# rail data still get mangled
$run = [['name', 'a test'],['A', 3, 4, 5, '', 2, 0, [5, 5, 's', 2, '']]];

# Store.pm line 379
$g->{warn} = 0;
push @$run, ['C', 5, 5, 3, '', 5, 0, [3, 4, 's', 5, '']];
like(capture_merged{$g->store_run($run)}, qr/a test.*already/s, 'duplicate rail');
pop @$run;

# Store.pm line 124
$run = [['name', 'another test'],['A', 3, 4, 5, '', 2, 0, [5, 5, 's', 2]]];
push @$run, ['C', 5, 5, 3, '', 5, 0];
$g->{warn} = 0;
$run->[-1][5] = 2;
like(capture_stderr{$g->store_run($run)}, qr/no connection from/i, 'to tile');

$g->{warn} = 0;
push @$run, ['L', 1, 1, 0, '', 3, 0, [3, 3, 'xs', 3, 22]];
$run->[0] = ['name', 'pillar'];
like(capture_merged{$g->store_run($run)}, qr/enough pillars/, 'enough pillars');

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
	# header line
	'no name in first line' => ['name' => qr/missing run name/i, 'run'], # 471
	# tile definition
	'wrong position' => ['abc' => qr/wrong tile pos/i, 'run'], # 431
	'wrong level' => ['level a' => qr/wrong level/i, 'run'], # 481
	'wrong ground plane' => ['_ 7 a' => qr/ground plane/, 'run'], # 499
	'helix elements' => ['22 xH1a'=> qr/helix/i, 'run'], # 540
	'open basket' => ['22 3Oa' => qr/no height.*no orient/si, 'run'], # 556,578
	'excess tile char' => ['22 Caa' => qr/excess/i, 'run'], # 564
	'wrong orientation' => ['22 Cx' => qr/wrong orient/i, 'run'], # 567
	'rail instead of tile' => ['22 sa' => qr/not a tile/i, 'run'], # 574
	'missing orientation' => ['22 C' => qr/missing tile orient/i, 'run'], # 576
	'wrong tile char' => ['22 %' => qr/wrong tile char/i, 'run'], # 581
	'no tile data and garbage' => ['22 3 y' => qr/no tile data/i, 'run'], # 583
	'no tile data' => ['33 3 sa' => qr/no tile data/i, 'run'], # 583
	'no further data' => ['22' => qr/further data/i, 'run'], # 586
	# marble data
	'excess marble char' => ['33 Ca oSad' => qr/excess/i, 'run'], # 608
	'max # of marbles' => ['44 Ca oa ob oc od oe' => qr/maximum/i, 'run'], # 613
	# rail data
	'wrong rail char' => ['22 Ca La' => qr/wrong rail char/i, 'run'], # 620
	'duplicate rail' => ['42 Ca sd sd' => qr/seen/i, 'run'], # 629
	'wrong direction' => ['22 Ca sx' => qr/wrong rail dir/i, 'run'], # 636
	'missing direction' => ['22 Ca s' => qr/missing rail dir/i, 'run'], # 638
	'excess rail char' => ['33 Ca sad' => qr/excess/i, 'run'], # 641
	'wrong rail data' => ['33 Ca yy' => qr/rail data/i, 'run'], # 645
	'max 3 rails' => ['44 Ca sa sb sc sd se' => qr/maximum/i, 'run'], # 649
	# rail end point
	'bridge elements' => ['41 xB9d' => qr/even number/i, 'run'], # 746
	'wrong rail char' => ['41 Ca xoa' => qr/wrong rail char/i, 'run'], # 753
	'outside' => ['14 Ca sa' => qr/outside/i, 'run'], # 753
	# material input
	'wrong element char' => ['1 %' => qr/unknown element/i, 'mat'], # 721
	'ambig set' => ['1 Tr' => qr/ambig set/i, 'mat'], # 723
	'unknown set' => ['1 Tux' => qr/unknown set/i, 'mat'], # 725
	'unknown line' => ['bla' => qr/unknown material/i, 'mat'], # 728
];
while (my($s, $l) = splice(@$line, 0, 2)) {
	$g->{warn} = 0;
	my $content = "test\n$l->[0]";
	if ($l->[2] eq 'run') {
		like(capture_stderr{$g->parse_run($content)}, $l->[1], $s);
	} else {
		like(capture_stderr{$g->parse_material($content)}, $l->[1], $s);
	}
}

done_testing();

#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use Capture::Tiny ':all';
use Game::MarbleRun::Store;

# all warnings are fatal
$SIG{__WARN__} = sub { die $_[0] };

ok(Game::MarbleRun::loc_lang('C'), 'switch language');

# create and populate database
my $g = Game::MarbleRun::Store->new(db => ':memory:', verbose => 1);

# check if DB is filled
like(capture_stdout{$g->list_elements()}, qr/Height/, 'element names filled');
like(capture_stdout{$g->list_sets()}, qr/Tip Tube/, 'set names filled');

# check all input methods
if ($^O eq 'linux') {
	my $owner = 'owner doe; 1 Starter Set';
	open STDIN, '-|', '/bin/echo', $owner;
	like(capture_stdout{$g->process_input()}, qr/doe/, 'process_input');
}

my $material = [['owner', 'john doe', '*'],[1, 'Starter Set']];
like(capture_stdout{$g->store_material($material)}, qr/john/, 'store material');
like(capture_stdout{$g->inventory(1)}, qr/40/, 'inventory');

my $run = [['name', 'basic_a'],['A', 3, 4, 5, '', 2, 0,[5, 5, 's',2],
	['o', 2, undef]],	['C', 5, 5, 3, '', 5, 0,[5, 8, 'm', 3]],
	['C', 5, 8, 3, '', 5, 0,[9, 6, 'l',1]], ['C', 9, 6, 0, '', 4, 0],
	['C', 10, 6, 0, '', 5, 0],['Z', 10, 7, 0, '', 1, 0]];
ok((capture_stdout{$g->store_run($run)}) eq '', 'store run');

# check correctness of predicting rail end points
ok(join('', $g->rail_xy('m', 5, 3, 1, '')) eq '81', 'rail_xy');
ok(join('', $g->rail_xy('m', 5, 3, 2, '')) eq '84', 'rail_xy');
ok(join('', $g->rail_xy('m', 5, 3, 4, '')) eq '24', 'rail_xy');
ok(join('', $g->rail_xy('m', 5, 3, 5, '')) eq '21', 'rail_xy');
ok(join('', $g->rail_xy('m', 4, 3, 1, '')) eq '72', 'rail_xy');
ok(join('', $g->rail_xy('m', 4, 3, 2, '')) eq '75', 'rail_xy');
ok(join('', $g->rail_xy('m', 4, 3, 4, '')) eq '15', 'rail_xy');
ok(join('', $g->rail_xy('m', 4, 3, 5, '')) eq '12', 'rail_xy');

done_testing();

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
my $g = Game::MarbleRun::Store->new(db => ':memory:');

### parse line checks: valid data ###
# all warnings are now fatal
$SIG{__WARN__} = sub { die $_[0] };

# store runs from instruction booklets. The test suite fails on warnings
$g->{warn} = 0;
for (glob('runs/* t/data/*')) {
	(my $name = $_) =~ s/.*\///;
	like(capture_stdout{$g->process_input($_)}, qr/checking/i, "run $name");
}
done_testing();

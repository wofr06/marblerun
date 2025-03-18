package Game::MarbleRun;

use v5.14;
use strict;
use warnings;

use DBI;
use Game::MarbleRun::I18N;
use Locale::Maketext::Simple (Style => 'gettext');

$Game::MarbleRun::VERSION = '1.17';
my $homedir = $ENV{HOME} || $ENV{HOMEPATH} || die "unknown homedir\n";
$Game::MarbleRun::DB_FILE = "$homedir/.gravi.db";
$Game::MarbleRun::DB_SCHEMA_VERSION = 16;

sub new {
	my ($class, %attr) = @_;
	my $self = {};
	bless $self => $class;
	$self->config(%attr);
}

sub config {
	my ($self, %attr) = @_;
	my %def = (
		db => $Game::MarbleRun::DB_FILE,
		verbose => 0,
		quiet => 0,
		relative => 0,
		motion => 0,
		yes => 0,
		outputfile => '',
		fill => 0);
	$self->{$_} = $attr{$_} || $def{$_} for keys %def;
	my $db = $self->{db};
	my $dbh = $self->connect_db($db) if ! exists $self->{dbh};
	$self->{dbh} = $dbh;
	# fetch some frequently used data from DB
	$self->{set_id} = $self->query_table('name,id', 'sets');
	$self->{set_name} = $self->query_table('id,name', 'sets');
	$self->{elem_name} = $self->query_table('char,name', 'element');
	$self->{people} = $self->query_table('id,name', 'person');
	$self->{run_ids} = $self->query_table('digest,id', 'run');
	$self->features();
	return $self;
}

sub features {
	my ($self) = @_;
	# Tile rules
	# symbol dir_in dir_out z_in z_out cond result speed
	#      0      1       2    3     4    5      6     7
	# direction M means middle (in or out), e.g. for vortex, drop, catcher
	# direction F means fly in (dir 0)/out straight ahead (catapult, trampolin)
	# cond = [n]o[dir] n marbles, direction dir must be present,
	# cond = n z difference at least |n|
	# cond = n1 and result = n2 state n1 becomes state n2 (S, U, xM, xV)
	# cond = 0 din, dout cannot be reversed
	# cond = 'r' din, dout and zin, zout can be reversed
	# result = [n]o[dir]: outgoing marble[s] in direction dir
	# zout > 0 : change of z to new value n, zout < 0 change to zout <= -n
	my $tile_r = [
		# sym   din dout    zin    zout    cond  result
		[ 'A',  '',   0,      0,      0,   'o0',   'o0'],
		[ 'A',  '',   2,      0,      0,   'o2',   'o2'],
		[ 'A',  '',   4,      0,      0,   'o4',   'o4'],
		[ 'C',   0,   4,      0,      0,   'r'],
		[ 'C',   1,   2,      0,      0,   'r'],
		[ 'D',   0, 'M',      0,      0,    -4],
		[ 'F',   0, 'F',      0,      7,     0,       1],
		[ 'G', 'M',   0,      0,      0,     4],
		[ 'G',   0,   0,      0,      0,     0],
		[ 'H',   3,   0,      0,      0,     0,       1],
		[ 'I',   3,   0,      0,      0,   'r'],
		[ 'J',   3,   0,      0,      7,      0,      1],
		[ 'J',   3,   0,      0,      0,      1,      1],
		[ 'J',   3,   0,      9,      7,      1,      1],
		[ 'K',   3, 'F',      0,      9,      0,      1],
		[ 'M',   3,  '',      0,      0, '2o0o3',  'o0'],
		[ 'N',   0,  '',      0,      0, 'o1o0',   'o1'],
		[ 'N',   0,  '',      0,      0, 'o3o0',   'o3'],
		[ 'N',   0,  '',      0,      0, 'o5o0',   'o5'],
		[ 'O', 'M',   0,      0,      0,    -3],
		[ 'P', 'M',  '',      0,      0, 'o0oM',   'o0'],
		[ 'P', 'M',  '',      0,      0, 'o2oM',   'o2'],
		[ 'P', 'M',  '',      0,      0, 'o4oM',   'o4'],
		[ 'Q',   3,   0,      0,      0,   'r'],
		[ 'R', 'F', 'F',      0,     -8,     3],
		[ 'S',   0,   2,      0,      0,      0,      1],
		[ 'S',   0,   4,      0,      0,      1,      0],
		[ 'S',   4,   0,      0,      0,      0,      1],
		[ 'S',   2,   0,      0,      0,      1,      0],
		[ 'T',   0,   4,      0,      0,   'r'],
		[ 'U',   0,   2,      0,      0,      0,      1],
		[ 'U',   0,   4,      0,      0,      1,      0],
		[ 'U',   4,   0,      0,      0,      0,      1],
		[ 'U',   2,   0,      0,      0,      1,      0],
		[ 'V',   0, 'M',      0,      0,    -4],
		[ 'V',   3, 'M',      0,      0,    -4],
		[ 'W',   2,   0,      0,      0,     0],
		[ 'W',   3,   0,      0,      0,     0],
		[ 'W',   4,   0,      0,      0,     0],
		[ 'W',   0,   3,      0,      0,     0],
		[ 'X',   0,   3,      0,      0,   'r'],
		[ 'X',   1,   4,      0,      0,   'r'],
		[ 'Y',   2,   0,      0,      0,     0],
		[ 'Y',   4,   0,      0,      0,     0],
		[ 'Y',   0,   2,      0,      0,     0],
		[ 'Z',   0,  '',      0,      0,     0],
		[ 'Z',   2,  '',      0,      0,     0],
		[ 'Z',   4,  '',      0,      0,     0],
		[ 'e',   3,  '',      0,      0,     0],
		['xA',   3,  '',      0,      0, 'o0o3',   'o0'],
		['xB',   3,   0,      0,      0,      0,      1],
		['xB',   3,   0,      0,      0,      1,      1],
		['xB',   0,   3,      0,      0,      1,      1],
		['xC',   0,   1,      0,      0,   'r'],
		['xC',   2,   3,      0,      0,   'r'],
		['xC',   4,   5,      0,      0,   'r'],
		['xD', 'F',   1,      7,      0,     1,       1],
		['xD', 'F',   1,      8,      0,     1,       1],
		['xD', 'F',   5,      7,      0,     0,       0],
		['xD', 'F',   5,      8,      0,     0,       0],
		['xD',   1,   1,      0,      0,     1],
		['xD',   5,   5,      0,      0,     0],
		['xF',  0, 'detail2', 0, '7*(detail1-1)', '3*(detail1-1)o0', 'o0'],
		['xH', 'detail %6', 0, 'detail', 0,  0],
		['xH', 'M',   0, 'detail+2',    0,     0],
		['xI',   0,   3,      0,      0,   'r'],
		['xI',   1,   2,      0,      0,   'r'],
		['xI',   4,   5,      0,      0,   'r'],
		['xK',   3, 'F',      0,     15,      0,      1],
		['xM',   0,   1,      7,      0,      0,      5],
		['xM',   0,   5,      7,      0,      4,      3],
		['xM',   0,   3,      7,      0,      2,      1],
		['xM',   2,   5,      7,      0,      0,      3],
		['xM',   2,   3,      7,      0,      4,      1],
		['xM',   2,   1,      7,      0,      2,      5],
		['xM',   4,   5,      7,      0,      0,      3],
		['xM',   4,   3,      7,      0,      4,      1],
		['xM',   4,   1,      7,      0,      2,      5],
		['xP',   0, 'M',      0,      0,   'oM',   'o3'],
		['xP',   3, 'M',      0,      0,   'oM',   'o0'],
		['xQ',   0,   1,      0,      0,   'r'],
		['xR', 'F', 'F',     10,      8,      0,      1],
		['xR', 'F', 'F',     10,      9,      0,      1],
		['xS',  '',   0,      0,      0,   'o0',   'o0'],
		['xS',  '',   1,      0,      0,   'o1',   'o1'],
		['xS',  '',   2,      0,      0,   'o2',   'o2'],
		['xS',  '',   3,      0,      0,   'o3',   'o3'],
		['xS',  '',   4,      0,      0,   'o4',   'o4'],
		['xS',  '',   5,      0,      0,   'o5',   'o5'],
		['xT',   5,  '',      2,      0,    '',      ''],
		['xT',   5,  '',      2,      0,  'o5',      ''],
		['xT',   5,  '',      2,      0,  '2o5',     ''],
		['xT',   5,  '',      2,      0,  '3o5',  '3o0'],
		['xV',   0, 'M',      0,      0,    -4],
		['xV',   2, 'M',      0,      0,    -4],
		['xV',   4, 'M',      0,      0,    -4],
		['xW',   0,   3,      0,      0,   'r'],
		['xW',   1,   3,      0,      0,     0],
		['xW',   4,   0,      0,      0,     0],
		['xX',   0,   3,      0,      0,   'r'],
		['xX',   1,   4,      0,      0,   'r'],
		['xX',   2,   5,      0,      0,   'r'],
		['xY',   0,   3,      0,      0,   'r'],
		['xY',   1,   2,      0,      0,   'r'],
		['xY',   4,   0,      0,      0,     0],
		['xZ',   3,  '',      0,      0, 'o0o3',   'o0'],
		['yC',   0,   4,      0,      0,   'r'],
		['yC',   1,   3,      0,      0,   'r'],
		['yH',   0,   3,      7,      0,   'r'],
		['yH',   1,   4,      7,      0,   'r'],
		['yH',   2,   5,      7,      0,   'r'],
		['yH',   3,   0,      7,      0,   'r'],
		['yH',   4,   1,      7,      0,   'r'],
		['yH',   5,   2,      7,      0,   'r'],
		['yI',   0,   3,      0,      0,   'r'],
		['yI',   1,   5,      0,      0,   'r'],
		['yK',   0,   0,      0,      0,   0],
		['yK',   1,   2,      1,      0,   0],
		['yK',   2,   2,      0,      0,   0],
		['yK',   3,   4,      1,      0,   0],
		['yK',   4,   4,      0,      0,   0],
		['yK',   5,   0,      1,      0,   0],
		['yK',   0,   1,      8,      7,   0],
		['yK',   1,   1,      7,      7,   0],
		['yK',   2,   3,      8,      7,   0],
		['yK',   3,   3,      7,      7,   0],
		['yK',   4,   5,      8,      7,   0],
		['yK',   5,   5,      7,      7,   0],
		['yM',   0,   'detail2',      0,      11,   'o0'. ''],
		['yM',   0,   'detail2',      0,      11,   '2o0'. ''],
		['yM',   0,   'detail2',      0,      11,   '3o0'. 'o0'],
		['yR',   2,   0,      0,      0,     0],
		['yR',   3,   0,      0,      0,     0],
		['yR',   4,   0,      0,      0,     0],
		['yR',   0,  '',     14,      7,     '',     ''],
		['yR',   0,  '',     14,      7,   'oM',     ''],
		['yR',   0,  '',     14,      7, 'oMo0',   'o9'],
		['yR',   3,  '',     14,      7,     '',     ''],
		['yR',   3,  '',     14,      7,   'oM',     ''],
		['yR',   3,  '',     14,      7, 'oMo0',   'o9'],
		['yS',   0,   3,      7,      7, 'fast', 'fast'],
		['yS',   1,   4,      7,      7, 'fast', 'fast'],
		['yS',   0,   2,      7,      0,      0,      3],
		['yS',   0,   5,      7,      0,      3,      0],
		['yT',   0,   3,      0,      0,   'r'],
		['yT',   1,   4,      0,      0,     1],
		['yT',   2,   5,      0,      0,     2],
		['yT',   0,   5,      7,      0,      2,      1],
		['yT',   0,   5,      7,      0,      1,      0],
		['yT',   1,   0,      7,      0,      2,      1],
		['yT',   1,   0,      7,      0,      0,      5],
		['yT',   2,   1,      7,      0,      1,      0],
		['yT',   2,   1,      7,      0,      0,      5],
		['yT',   3,   2,      7,      0,      2,      1],
		['yT',   3,   2,      7,      0,      1,      0],
		['yT',   4,   3,      7,      0,      2,      1],
		['yT',   4,   3,      7,      0,      0,      5],
		['yT',   5,   4,      7,      0,      1,      0],
		['yT',   5,   4,      7,      0,      0,      5],
		['yW',   2,   0,      0,      0,     0],
		['yW',   5,   3,      0,      0,     0],
		['yW',   0,   3,      0,      0,   'r'],
		['yX',   0,   4,      0,      0,   'r'],
		['yX',   1,   5,      0,      0,   'r'],
		['yX',   2,   3,      0,      0,   'r'],
		['yY',   0,   3,      0,      0,   'r'],
		['yY',   4,   5,      0,      0,   'r'],
		['yY',   2,   0,      0,      0,     0],
		['zA',  '',   0,      0,      0,   'o0',   'o0'],
		['zE',   0,   1,      0,     14,     0],
		['zF',   0,   3,      0,      0,     0],
		['zL',   0,   3,      0,      8,     0],
		['zQ',   0,   3,      0,      0,     0],
		['zQ',   1,   3,      0,      0,     0],
		['zQ',   5,   3,      0,      0,     0],
		['zS',   0,   2,      4,      0,     0,    1],
		['zS',   0,   4,      4,      0,     1,    0],
		['zT',   0,   3,      0,      0,     0],
		['zZ',   0,  '',      0,      0,     0],
	];
	# expand symmetric tile rules
	for my $t (@$tile_r) {
		if ($t->[5] eq 'r') {
			$t->[5] = 0;
			push @$tile_r, [$t->[0], $t->[2], $t->[1], $t->[4], $t->[3], 0];
		}
	}
	# Rails
	# symbol integer length z_min z_max special
	#      0              1     2     3       4
	my $rail = [
		['a',  2,  6,  7,        0],
		['b',  4, 13, 15,        0],
		['c',  1,  5,  7,       -1],
		['d',  1,  5,  7,        1],
		['e',  1,  0,  3,        0],
		['g',  5,  0,  6,   'fast'], # fast rail
		['l',  4,  0,  8,        0],
		['m',  3,  0,  7,        0],
		['q',  5,  0,  6,   'slow'], # slow rail
		['s',  2,  0,  5,        0],
		['t',  0,  6,  8,        0],
		['u',  4,  0,  9,   'hole'],
		['v',  4,  0,  4,   'hole'],
		['xa', 4,  3,  7,        0],
		['xb', 4,  0,  0, 'length'], # detail: length
		['xl', 4,  0,  0,        0],
		['xm', 3,  0,  0,        0],
		['xs', 2,  0,  0,        0],
		['xt', 1,  7,  7,    'dir'], # detail: direction
	];
	# directions
	$self->{dirchr} = [qw(↑  ↗  ↘  ↓  ↙  ↖ )];
	# colors
	$self->{srgb} = {
		S=>'#d5d5d5',
		R=>'#d54545',
		G=>'#45d545',
		B=>'#45d5d5',
		A=>'#ffd700'};
	$self->{color} = {
		R => loc('red'), r => 'red',
		G => loc('green'), g => 'green',
		B => loc('blue'), b => 'blue',
		S => loc('silver'), s => 'silver',
		A => loc('gold'), a => 'gold'};
	# initial time to move marbles across 1 tile
	$self->{time0} = 10;
	# fraction of size for green hexagon in tile
	$self->{twoby3} = 2/3.;
	$self->{r_ball} = 0.1;
	#Position of marbles on tiles
	my %offset = (A => 0.25, 'xF' => 0, M => 2*$self->{r_ball},
		N => 1./24.+$self->{r_ball}, P => 1./12.+$self->{r_ball},
		xA => 0.3, xS => 0.375, xZ => -0.3,
		xB => [[-0.2, -0.3], [0.2, -0.3]], Z => 1.5*$self->{r_ball},
		xK => [[-0.2, -0.3], [-0.2, 0.3], [0.2, -0.3], [0.2, 0.3]],
		xT => -0.6, zA => 0.25,
	);
	push @{$self->{rules}{$_->[0]}}, $_ for @$tile_r;
	$self->{rail}{$_->[0]} = $_ for @$rail;
	$self->{offset}{$_} = $offset{$_} for keys %offset;
	# conn0/1: possible rail directions for tiles with orientation a at z=0/z!=0
	my ($conn0, $conn1);
	for my $t (@$tile_r) {
		my ($elem, $din, $dout, $z1, $z2, $cond, $res) = @$t;
		$conn0->{$elem}{$din} = 1 if $din !~ /^[FMRd]?$/ and $z1 eq '0';
		$conn0->{$elem}{$1} = 1 if $res and $res =~ /^\d?o(.)$/ and $z2 eq '0';
		$conn0->{$elem}{$dout} = 1 if $dout !~ /^[FMR]?$/ and $z2 eq '0';
		$conn1->{$elem}{$z1}{$din} = 1 if $din !~ /^[FMR]?$/ and $z1 ne '0';
		$conn1->{$elem}{$z2}{$dout} = 1 if $dout !~ /^[FMR]?$/ and $z2 ne '0';
	}
	$conn0->{$_} = [sort grep {/^\d$/} keys %{$conn0->{$_}}] for keys %$conn0;
	$self->{conn0} = $conn0;
	for my $e (sort keys %$conn1) {
		$conn1->{$e}{$_} = [sort keys %{$conn1->{$e}{$_}}] for keys %{$conn1->{$e}};
	}
	$self->{conn1} = $conn1;
}

sub connect_db {
	my ($self, $sqlfile) = @_;
	my $no_db = ! -s $sqlfile;
	my $dbh = DBI->connect("DBI:SQLite:$sqlfile", '','', {RaiseError=>1})
		or die "Could not connect to database: $DBI::errstr";
	create_tables($dbh) if $no_db;
	# fetch db version if table config exists;
	my $vers = 0;
	my $sth = $dbh->table_info(undef, '%', 'config', 'TABLE');
	my $res = $sth->fetchall_arrayref();
	($vers) = @{($dbh->selectall_array("SELECT vers FROM config"))[0]} if @$res;
	if ($vers < $Game::MarbleRun::DB_SCHEMA_VERSION) {
		$self->error("The current DB schema version is %1, you have only %2\n",
		$Game::MarbleRun::DB_SCHEMA_VERSION, $vers);
		my $yn = $self->prompt(loc("Upgrade the DB now?"));
		my $Y = loc('Y');
		create_tables($dbh) if $yn =~ /^[y$Y]/i;
		upgrade_run_tile($dbh) if $yn =~ /^[y$Y]/i and $vers < 11;
	}
	return $dbh;
}

sub upgrade_run_tile {
	my ($dbh) = @_;
	my $sql = <<EOF;
PRAGMA foreign_keys=off;
BEGIN TRANSACTION;
CREATE TABLE IF NOT EXISTS `run_tile2` (
	id INTEGER NOT NULL,
	run_id INTEGER NOT NULL,
	element TEXT,
	posx INTEGER,
	posy INTEGER,
	posz INTEGER,
	orient INTEGER,
	detail INTEGER,
	level INTEGER,
	FOREIGN KEY (run_id) REFERENCES run (id)
		ON DELETE CASCADE ON UPDATE NO ACTION
);
INSERT INTO run_tile2(id,run_id,element,posx,posy,posz,orient,detail,level)
SELECT id,run_id,element,posx,posy,posz,orient,detail,level
FROM run_tile;
DROP TABLE run_tile;
ALTER TABLE run_tile2 RENAME TO run_tile;
COMMIT;
PRAGMA foreign_keys=on;
EOF
	$dbh->do($_) for split /;/, $sql;
}

sub create_tables {
	my ($dbh) = @_;
	my $sql = <<EOF;
CREATE TABLE IF NOT EXISTS `config` (
	vers INTEGER UNIQUE,
	main_user INTEGER
);
UPDATE config SET vers=$Game::MarbleRun::DB_SCHEMA_VERSION;
INSERT OR IGNORE INTO config (vers) VALUES($Game::MarbleRun::DB_SCHEMA_VERSION);
DROP TABLE IF EXISTS `element`;
CREATE TABLE IF NOT EXISTS `element` (
	char TEXT PRIMARY KEY,
	name TEXT
);
DROP TABLE IF EXISTS `sets`;
CREATE TABLE IF NOT EXISTS `sets` (
	id INTEGER PRIMARY KEY,
	name TEXT UNIQUE
);
DROP TABLE IF EXISTS `set_element`;
CREATE TABLE IF NOT EXISTS `set_element` (
	sets_id integer,
	element TEXT,
	count integer,
	FOREIGN KEY (sets_id) REFERENCES sets (id)
		ON DELETE CASCADE ON UPDATE NO ACTION
);
CREATE TABLE IF NOT EXISTS `person` (
	id INTEGER PRIMARY KEY,
	name TEXT UNIQUE,
	comment TEXT
);
CREATE TABLE IF NOT EXISTS `person_set` (
	person_id INTEGER,
	set_id INTEGER,
	count INTEGER,
	comment TEXT,
	FOREIGN KEY (person_id) REFERENCES person (id)
		ON DELETE CASCADE ON UPDATE NO ACTION,
	FOREIGN KEY (set_id) REFERENCES sets (id)
		ON DELETE CASCADE ON UPDATE NO ACTION
);
CREATE TABLE IF NOT EXISTS `person_elem` (
	person_id INTEGER,
	element TEXT,
	count INTEGER,
	comment TEXT,
	FOREIGN KEY (person_id) REFERENCES person (id)
		ON DELETE CASCADE ON UPDATE NO ACTION
);
CREATE TABLE IF NOT EXISTS `run` (
	id INTEGER PRIMARY KEY,
	name TEXT,
	digest TEXT UNIQUE,
	date TEXT DEFAULT CURRENT_DATE,
	source TEXT,
	person_id INTEGER,
	size_x INTEGER,
	size_y INTEGER,
	layers INTEGER,
	marbles INTEGER
);
CREATE TABLE IF NOT EXISTS `run_tile` (
	id INTEGER NOT NULL,
	run_id INTEGER NOT NULL,
	element TEXT,
	posx INTEGER,
	posy INTEGER,
	posz INTEGER,
	orient INTEGER,
	detail INTEGER,
	level INTEGER,
	FOREIGN KEY (run_id) REFERENCES run (id)
		ON DELETE CASCADE ON UPDATE NO ACTION
);
CREATE TABLE IF NOT EXISTS `run_rail` (
	id INTEGER PRIMARY KEY,
	run_id INTEGER NOT NULL,
	element TEXT,
	direction INTEGER,
	tile1_id INTEGER,
	tile2_id INTEGER,
	detail INTEGER,
	FOREIGN KEY (run_id) REFERENCES run (id)
		ON DELETE CASCADE ON UPDATE NO ACTION
);
CREATE TABLE IF NOT EXISTS `run_marble` (
	run_id INTEGER,
	tile_id INTEGER,
	orient INTEGER,
	color TEXT,
	FOREIGN KEY (run_id) REFERENCES run (id)
		ON DELETE CASCADE ON UPDATE NO ACTION
);
CREATE TABLE IF NOT EXISTS `run_comment` (
	run_id INTEGER,
	tile_id INTEGER,
	comment,
	FOREIGN KEY (run_id) REFERENCES run (id)
		ON DELETE CASCADE ON UPDATE NO ACTION
);
CREATE TABLE IF NOT EXISTS `run_no_elements` (
	run_id INTEGER,
	board_x INTEGER,
	board_y INTEGER,
	FOREIGN KEY (run_id) REFERENCES run (id)
		ON DELETE CASCADE ON UPDATE NO ACTION
);
EOF
	# use arrayrefs to keep the ordering (letters 'cwy' unused)
	my $elems = [
		# Basic elements #
		_=>'Base Plate', '@'=>'Small Base Plate', '^'=>'Transparent Level',
		'='=>'Small Transparent Level', o=>'Ball',
		1=>'Height Tile large', '+'=>'Height Tile small', A=>'Launch Pad',
		Z=>'Landing', e=>'Finish Line', C=>'Curve', X=>'Junction',
		W=>'3 in 1', Y=>'2 in 1', S=>'Switch', M=>'Magnetic Cannon',
		V=>'Vortex', D=>'Freefall (Drop)', G=>'Catcher', P=>'Splash',
		xG=>'Basic Tile',
		# Extensions
		xA=>'Zipline Begin', xZ=>'Zipline End', F=>'Flipper', H=>'Hammer',
		J=>'Jumper', K=>'Scoop', xK=>'Catapult', N=>'Volcano', Q=>'Looping',
		T=>'Tunnel Curve', U=>'Tunnel Switch', I=>'Tunnel Straight',
		t=>'Tunnel Vertical', O=>'Open Basket', xR=>'Transfer',
		R=>'Trampoline', r=>'Angled Base', xB=>'Bridge Tile', xT=>'Tip Tube',
		xF=>'Lifter', f=>'Lift Tube Element', xi=>'Lift in', xj=>'Lift out',
		xH=>'Spiral', i=>'Spiral in', j=>'Spiral out', h=>'Spiral Curve',
		L=>'Pillar', xL=>'Tunnel Pillar', B=>'Balcony', E=>'Double Balcony',
		xM=>'Mixer', yS=>'Splitter', xD=>'Dipper', xS=>'Spinner',
		yH=>'Helix', yT=>'Turntable', xQ=>'Loop Curve', xV=>'Vortex 3 in',
		xC=>'Curve 3x small', yC=>'Curve 2x large', yK=>'Carousel',
		xI=>'Straight with 2 Curves', xX=>'Straight 3x', xW=>'2x 2 in 1 left',
		yW=>'2x 2 in 1 right', xY=>'2 in 1 left with Curve',
		yY=>'2 in 1 right with Curve', yX=>'3 Curves, 2 crossing',
		yI=>'Cross Straight and Curve', xP=>'Color Swap', yR=>'Releaser',
		yM=>'Vertical Cannon',
		'z+'=>'Light Tile Small', z1=>'Light Tile large', z2=>'Light Tile Base',
		zA=>'DomeStarter', zE=>'Elevator', zF=>'FinishTrigger', zL=>'Lever',
		zQ=>'Queue', zS=>'DropDownSwitch', zT=>'Trigger', zZ=>'FinishArena',
		# Rails
		s=>'Rail Short', m=>'Rail Medium', l=>'Rail Long', b=>'Rail Bernoulli',
		v=>'Drop Rail Concave', u=>'Drop Rail Convex', g=>'Rail Overlong',
		q=>'Rail Overlong slow', xb=>'Bridge Element', xa=>'Zipline Rail',
		xs=>'Wall Small', xm=>'Wall Medium', xl=>'Wall Long',
		a=>'Rail Bernoulli short', c=>'Rail counter clockwise',
		d=>'Rail clockwise', xt=> 'Flextube',
		# Self made elements
		2=>'Height tile 2 units', 3=>'Height tile 3 units',
		4=>'Height tile 4 units', 5=>'Height tile 5 units',
		6=>'Height tile 6 units', 7=>'Height tile 7 units',
		8=>'Height tile 8 units', 9=>'Height tile 9 units',
	];
	my $sets = [
		# Starter Sets
		'Starter Set', 1, ['_'=>4, '^'=>2, o=>6, 1=>40, '+'=>12, C=>21, X=>3,
			S=>2, W=>1, V=>1, A=>1, M=>1, l=>3, m=>6, s=>9, e=>1, G=>2,
			D=>1, P=>1, Z=>1, xG=>5],
		'XXL Starter Set', 2, ['_'=>8, '^'=>4, o=>12, 1=>80, '+'=>24, C=>42, X=>6,
			S=>4, W=>2, V=>2, A=>2, M=>2, l=>6, m=>12, s=>18, e=>2, G=>4, D=>2,
			P=>2, Z=>2, H=>1, Q=>1, xG=>10],
		'Starter Set Vertical', 3, ['_'=>4, '^'=>1, o=>6, 1=>20, '+'=>9, C=>28,
			X=>4, S=>2, W=>1, V=>1, A=>1, M=>1, l=>3, m=>6, s=>9, e=>1, G=>2,
			D=>1, P=>1, Z=>1, B=>16, E=>4, L=>8, xL=>4, a=>2, c=>3, d=>3,
			xs=>1, xm=>2, xl=>2, xG=>5],
		'Starter Set Speed', 4, ['_'=>6, '^'=>2, '='=>2, o=>7, 1=>56, '+'=>12,
			C=>28, X=>4, S=>2, W=>1, V=>1, A=>1, M=>2, l=>3, m=>6, s=>9, e=>1,
			G=>2, D=>1, P=>1, Z=>2, a=>2, b=>2, c=>2, d=>2, g=>2, q=>2, u=>1,
			v=>1, xH=>1, F=>1, T=>2, I=>1, U=>1, t=>1, Q=>1, xG=>8],
		'Action Set Focus', 39, ['@'=>3, '('=>1, ')'=>1, '='=>1, xS=>1, C=>7,
			W=>1, V=>1, X=>1, M=>1, S=>2, P=>1, G=>2, D=>1, Z=>1, xG=>3, '+'=>6,
			1=>12, l=>2, m=>4, s=>6, o=>3, e=>1],
		# Extension Sets
		'Building Extension', 5, [_=>2, '^'=>1, 1=>8, '+'=>4, S=>2, W=>1, V=>1,
			e=>1, G=>2, D=>1, P=>1, Z=>1, xG=>5],
		'Trax', 6, [1=>16, '+'=>8, C=>7, X=>1, o=>6, l=>1, m=>2, s=>3],
		'Tunnel', 7, [_=>2, T=>4, I=>2, U=>2, t=>2, O=>2, b=>2, u=>1, v=>1],
		'Lifter', 8, [xF=>1, o=>7, '^'=>1, 1=>8, '+'=>4, f=>2, xi=>1, xj=>1,
			l=>1, m=>2, s=>3],
		'Bridges Extension', 9, [xB=>3, g=>2, q=>2, xb=>12, l=>1, m=>2, s=>3,
			o=>6],
		'Extension Vertical', 10, [B=>16, L=>8, xL=>4, xm=>2, xl=>2],
		# Advent 2021
		'Advent 21', 31, [xX=>1, c=>3, yC=>1, 1=>4, xR=>1, xQ=>1, xV=>1, yX=>1,
			t=>1, xC=>1, d=>3, g=>1, q=>1, xI=>1, U=>1, yI=>1, a=>2, xY=>1,
			I=>1, xH=>1, i=>1, j=>1, h=>6, yY=>1, xW=>1, yW=>1, T=>2, xS=>1,
			o=>1, '='=>1],
		# Action tiles
		'Hammer', 11, [H=>1, o =>1, l=>1, m=>2, s=>3],
		'Looping', 12, [Q=>1, l=>1, m=>2, s=>3],
		'Volcano', 13, [N=>1, l=>1, m=>2, s=>3],
		'Transfer', 14, [xR=>3, l=>1, m=>2, s=>3],
		'Flipper', 15, [F=>1, l=>1, m=>2, s=>3],
		'Scoop', 16, [K=>1, o=>2, l=>1, m=>2, s=>3],
		'Cable Car (Zipline)', 17,[xA=>1, xZ=>1, o=>1, l=>1, m=>2, s=>3, xa=>1],
		'Trampoline', 18, [R=>2, r=>2],
		'Magnetic Cannon', 19, [M=>1, o=>3],
		'Jumper', 20, [J=>1, l=>1, m=>2, s=>3],
		'Tip Tube', 21, [xT=>1, o=>1, l=>1, m=>2, s=>3],
		'Spiral', 22, [xH=>2, i=>2, j=>2, h=>12],
		'Splitter', 23, [yS=>1],
		'Mixer', 24, [xM=>1],
		'Catapult', 25, [xK=>1, o=>4],
		# 2021
		'Dipper', 26, [xD=>1, 1=>4, o=>1],
		'Spinner', 27, [o=>6, xS=>1],
		'Flextube', 28, [xt=>4, 1=>4],
		'Helix', 29, [yH => 1],
		'Turntable', 30, [yT => 1],
		# 2022
		'Color Swap', 32, [xP => 3],
		'Carousel', 33, [yK => 1],
		# Game sets
		'Game Flow', 34, ['@'=>2, '='=>1, C=>7, V=>1, G=>1, X=>1, A=>1, Z=>1,
			1=>11, '+'=>1, xt=>2, l=>1, m=>2, s=>3, o=>1],
		'Game Impact', 35, ['@'=>3, C=>7, X=>1, A=>1, H=>1, Z=>1, 1=>4, l=>2,
			m=>2, s=>3, o=>1],
		'Game Course', 36, ['@'=>4, X=>1, A=>1, S=>1, Z=>1, 1=>6, W=>1, xQ=>1,
			yI=>1, xW=>1, yW=>1, xY =>1, yY=>1, yX=>1, l=>2, m=>2, s=>3, o=>2],
		'Multiform', 40, ['*'=>14, xS=>1, 1=>10, '+'=>2, C=>6, X=>1, Z=>1, o=>1,
			K=>1, l=>2, m=>4, s=>4],
		# 2023
		'Releaser', 37, [yR => 1],
		# 2024
		'Vertical Cannon', 38, [yR => 1],
	];
	# create tables (only single sql statements allowed)
	$dbh->do($_) for split /;/, $sql;
	# populate tables
	$sql = 'INSERT INTO element (name,char) VALUES (?,?)';
	my $sth = $dbh->prepare($sql);
	while (@$elems) {
		my ($char, $name) = splice(@$elems, 0, 2);
		$sth->execute($name, $char);
	}
	$sql = 'INSERT INTO set_element (sets_id,element,count) VALUES (?,?,?)';
	$sth = $dbh->prepare($sql);
	while (@$sets) {
		my ($name, $set_id, $set) = splice(@$sets, 0, 3);
		$dbh->do("INSERT INTO sets (id,name) VALUES ('$set_id','$name')");
		while (@$set) {
			my ($c, $num) = splice(@$set, 0, 2);
			$sth->execute($set_id, $c, $num);
		}
	}
}

sub finish {
	my ($self) = @_;
	$self->{dbh}->disconnect();
}

sub query_table {
	my ($self, $what, $where, $when) = @_;
	my $sql = "SELECT $what FROM $where";
	$sql .= " WHERE $when" if $when;
	my $res = $self->{dbh}->selectall_arrayref($sql);
	return {map {$_->[0], $_->[1]} grep {defined $_->[1]} @$res};
}

sub prompt {
	my ($self, $str) = @_;
	# get the various localized Y/N combinations
	my $Y_or_N = loc('Y') . '/' . loc('N');
	# always accept the english form y/n
	(my $YN = $Y_or_N) =~ s/\//YN/;
	my $answer = $self->{yes} ? 'Y' : $self->{answer} ;
	return $answer if $answer and $answer =~ /[$YN]/;
	warn "$str ", lc ($Y_or_N), " ($Y_or_N) ", loc("to all\n");
	$answer = <STDIN>;
	$answer ||= lc loc('N');
	# default answer is no
	($answer) =~ /([$YN])/i;
	$self->{answer} = $answer;
	return $answer;
}

sub num2pos {
	my ($self, $posx, $posy, $plain) = @_;
	$posx ||= 0;
	$posy ||= 0;
	my $loc_pos = loc('pos');
	my $loc_plane = loc('plane');
	if (! $self->{relative} and $posx < 36 and $posy < 36) {
		$posx = chr(87+$posx) if $posx > 9;
		$posy = chr(87+$posy) if $posy > 9;
		return $plain ? "$posy$posx" : "$loc_pos $posy$posx";
	}
	my $bx = int(($posx + 5)/6);
	$posx = (($posx - 1) % 6) + 1;
	my $by = int(($posy + 4)/5);
	$posy = (($posy - 1) % 5) + 1;
	return "$by,$bx $posx$posy" if $plain;
	return "$loc_plane $by,$bx $loc_pos $posy$posx";
}

sub is_heightelem {
	my ($self, $sym) = @_;
	return $sym =~ /^[+\dEL]$|^xL$/;
}

sub error {
	my ($self, $str, @args) = @_;
	my $line = $self->{line} ? loc(" line %1", $self->{line}) : '';
	$str = loc($str, @args);
	$str .= " (file $self->{fname}$line!)" if $self->{fname};
	$self->{warn}++;
	my $locstr = loc('exit');
	die "$str\n" if $str =~ /$locstr|exit/i;
	warn "$str\n";
}

sub adjust {
	# print with Locale::Maketext has some problems, use a dirty hack
	my ($str,$width) = @_;
	$str ||= '';
	my $loc = loc($str);
	# calculate it by counting the high bits assuming 1 column chars only
	my $num = $width - length $loc;
	$num += unpack('%B4', $_) - 1 for grep {ord > 191} split '', $loc;
	$num = 0 if $num < 0;
	return $loc . " " x $num;
}

sub list_elements {
	my ($self, @args) = @_;
	my @items;
	push @items, split /,/ for @args;
	my $name = $self->{elem_name};
	my $nr = {reverse %$name};
	if (@items) {
		$name = {map {$_, $name->{$_}} grep {exists $name->{$_}} @items};
		if (! keys %$name) {
			for my $i (@items) {
				$name->{$nr->{$_}} = $_ for (grep {loc($_) =~ /$i/} keys %$nr);
			}
		}
	}
	# multi column output depending on width of names to be printed
	my $cols = 3;
	my @width = (0, 76, 36, 23);
	for (values %$name) {
		$cols-- if length loc($_) > $width[$cols];
	}
	my $fmt = "%2s %$width[$cols]s%s";
	my $i = 1;
	my @sep = ("\n", ' ', ' ');
	printf($fmt, $_, adjust($name->{$_}, $width[$cols]), $sep[$i++ % $cols])
		for sort keys %$name;
	print "\n" if ($i - 1) % $cols;
}

sub list_sets {
	my ($self, @args) = @_;
	my (@nums, $sel_id);
	push @nums, split /,/ for @args;
	my $set_id = $self->{set_id};
	my $rev_id = {reverse %$set_id};
	for my $n (@nums) {
		if (exists $rev_id->{$n}) {
			$sel_id->{$rev_id->{$n}} = $n;
		} else {
			for (keys %$set_id) {
				$sel_id->{$_} = $set_id->{$_} if $_ =~ /$n/i;
				my $loc_n = loc($_);
				$sel_id->{$_} = $set_id->{$_} if $loc_n =~ /$n/i;
			}
		}
	}
	if (! $self->{verbose} and ! $sel_id) {
		my @sep = ("\n", ' ');
		my $i = 1;
		printf "%2d %-30s %s", $set_id->{$_}, loc($_), $sep[$i++ % 2]
			for sort {$set_id->{$a} <=> $set_id->{$b}} keys %$set_id;
			print "\n" if ! ($i % 2);
		return;
	}
	$sel_id = $set_id if ! @nums;
	my $name = $self->{elem_name};
	for (sort {$sel_id->{$a} <=> $sel_id->{$b}} keys %$sel_id) {
		my $id = $sel_id->{$_};
		my $elems = $self->query_table(
			'element,count', 'set_element', "sets_id=$id"
		);
		printf("%s (id %d)\n", loc($_), $id);
		my $cols = 3;
		my @width = (0, 74, 34, 21);
		for (values %{$self->{elem_name}}) {
			$cols-- if length loc($_) > $width[$cols];
		}
		my $i = 1;
		my @sep = ("\n", ' ', ' ');
		printf("%2d x %$width[$cols]s%s", $elems->{$_},
			adjust($name->{$_}, $width[$cols]), $sep[$i++ % $cols])
			for sort {$elems->{$b} <=> $elems->{$a}} keys %$elems;
		print "\n" if ($i - 1) % $cols;
	}
}

sub get_run_elements {
	my ($self, $id) = @_;
	my $dbh = $self->{dbh};
	# get numbers of rails and hexagonal elements required
	my $sql = "SELECT element,count(element) FROM run_rail WHERE run_id=$id
		GROUP BY element ORDER BY count(element) DESC";
	my $num = {map {$_->[0], $_->[1]} $dbh->selectall_array($sql)};
	$sql =~ s/run_rail/run_tile/;
	my $num2 = {map {$_->[0], $_->[1]} $dbh->selectall_array($sql)};
	$num->{$_} = $num2->{$_} for keys %$num2;
	$num->{xG} += $num->{$_} for grep {$num->{$_}} (split '', 'DGINPTZ');
	# double balconies are counted twice
	$num->{E} /= 2 if exists $num->{E};
	$sql = "SELECT element,detail FROM run_tile WHERE run_id=$id
		AND detail is NOT NULL";
	# number of height tiles (1) will be recalculated
	my $d = {map {$_->[0], $_->[1]} $dbh->selectall_array($sql)};
	for (keys %$d) {
		# special cases falling bridges, spiral and lift
		if ($d eq 'xB') {
			$num->{xb} += $d->[$_] - 1;
		} elsif ($d eq 'xH') {
			$num->{h} += $d->[$_] - 2;
			$num->{i}++;
			$num->{j}++;
		} elsif ($d eq 'xF') {
			$num->{f} += substr($d->[$_], 0, 1) - 2;
			$num->{xi}++;
			$num->{xj}++;
		} elsif ($d eq 'R') {
			$num->{r} += length $d->[$_];
		}
	}
	# no tile on top of height elements
	return $num;
}

sub get_owned_elements {
	my ($self, $id) = @_;
	# elements from sets, default is one starter set
	my ($set, $num);
	my $what = 'element,count';
	if ($id) {
		$set = $self->query_table('set_id,count', 'person_set',"person_id=$id");
		# additional or missing elements
		$num = $self->query_table($what, 'person_elem', "person_id=$id");
	}
	$set = {$self->{set_id}{'Starter Set'} => 1} if ! keys %$set;
	for my $s (keys %$set) {
		my $set_elems = $self->query_table($what, 'set_element', "sets_id=$s");
		$num->{$_} += $set->{$s}*$set_elems->{$_} for keys %$set_elems;
	}
	return $num;
}

sub check_num_elements {
	my ($self, $needed, $owned) = @_;
	return 0 if ! $owned;
	# the 1 elements were counted in height units
	for (2 .. 9) {
		next if ! exists $needed->{$_};
		$needed->{1} += $_*$needed->{$_};
		delete $needed->{$_};
	}
	# 2 unused small height tiles can be replaced for a large one
	$owned->{1} += int(($owned->{'+'} - ($needed->{'+'} || 0))/2);
	# self made larger height tiles can be used
	$owned->{1} += ($_ - 2)* $owned->{$_} for grep {$owned->{$_}} 2 .. 9;
	# switch and 2in1 are the same element
	if (exists $needed->{Y}) {
		$needed->{S} += $needed->{Y};
		delete $needed->{Y};
	}
	# now compare owned and needed elements
	my $missing;
	for my $elem (keys %$needed) {
		next if ! $owned;
		next if exists $owned->{$elem} and $owned->{$elem} >= $needed->{$elem};
		$missing->{$elem} = $needed->{$elem} - ($owned->{$elem} || 0);
	}
	return $missing;
}

sub owner_of_set_id {
	my ($self, $string) = @_;
	my $dbh = $self->{dbh};
	# return id or main user
	return ($dbh->selectall_array("SELECT main_user FROM config"))[0][0]
		if ! $string;
	return $string if $string =~ /^\d+$/ and exists $self->{people}{$string};
	# check for a given user name string and return id, if unique match
	my @ids = grep {$self->{people}{$_} =~ /$string/i} keys %{$self->{people}};
	return $ids[0] if @ids == 1;
	# otherwise present a list of matching users having material
	my $ids = join ',', @ids;
	my $people = $self->query_table('person_id,name', 'person_set,person',
		"person_id=person.id AND person.id in ($ids)");
	return (keys %$people)[0] if keys %$people == 1;
	$people = $self->{people} if ! keys %$people;
	printf("%3d %s\n", $_, $people->{$_}) for sort {$a <=> $b} keys %$people;
	return $self->get_id ();
}

sub get_id {
	my ($self, $str, @ids) = @_;
	return undef if ! @ids;
	return $ids[0] if @ids == 1;
	$str = loc($str) if $str;
	$str .= $str ? ":\n" : '';
	warn loc("%1Please enter an id from the list above\n", $str);
	my $res = <STDIN>;
	return if ! $res;
	chomp $res;
	return $res if grep {$res eq $_} @ids;
	return undef;
}

sub fetch_run_data {
	my ($self, $id) = @_;
	my $sql = "SELECT * FROM run WHERE id=$id";
	my $res_meta = ($self->{dbh}->selectall_array($sql))[0];
	die loc("No run with id %1 existing\n", $id) if ! $res_meta;
	$sql = "SELECT * FROM run_tile WHERE run_id=$id ORDER BY posx,posy";
	my $res_tile = $self->{dbh}->selectall_arrayref($sql);
	$sql = "SELECT r.element,r.direction,tile1_id,t1.level,tile2_id,t2.level
		,r.detail FROM run_rail AS r, run_tile AS t1, run_tile AS t2
		WHERE r.run_id=$id AND tile1_id=t1.id AND tile2_id=t2.id
		AND t1.run_id=$id AND t2.run_id=$id";
	my $res_rail = $self->{dbh}->selectall_arrayref($sql);
	# treat finish line like a tile, it has no connection at the end
	$sql = "SELECT r.id,r.run_id,r.element,posx,posy,posz,r.direction,r.detail,t.level
		FROM run_rail AS r, run_tile AS t WHERE r.run_id=$id AND tile1_id=t.id
		AND t.run_id=$id and r.element = 'e'";
	my $tiles_e = $self->{dbh}->selectall_arrayref($sql);
	for my $t (@$tiles_e) {
		($t->[3], $t->[4]) = $self->to_position($t->[3], $t->[4], $t->[6], 1);
		push @$res_tile, $t;
	}

	$sql = "SELECT tile_id,orient,color FROM run_marble WHERE run_id=$id";
	my $res_marble = $self->{dbh}->selectall_arrayref($sql);
	$sql = "SELECT board_x,board_y FROM run_no_elements WHERE run_id=$id";
	my $res_excl = $self->{dbh}->selectall_arrayref($sql);
	return ($res_meta, $res_tile, $res_rail, $res_marble, $res_excl);
}

sub get_file_name {
	my ($self, $name, $ext, $str, $nocheck) = @_;
	$str = $str ? " ($str)\n" : "\n";
	if (! $name) {
		if ($ext) {
			warn(loc("Please enter file name without .%1%2", $ext, $str));
		} else {
			warn(loc("Please enter a file name"), $str);
		}
		$name = <STDIN>;
		chomp $name;
		return '' if ! $name;
		if ($name !~ /^[\w\.\/]+/) {
			$self->error("Name must start with an alphanum char");
			return '';
		}
	}
	$name = $ext ? "$name.$ext" : $name;
	return $name if $nocheck;
	if ($name and -r $name) {
		my $yn = $self->prompt(loc("File %1 existing, overwrite it?", $name));
		my $Y = loc('Y');
		return '' if $yn !~ /^[y$Y]/i;
	}
	return $name || '';
}

sub export_marble_run {
	my ($self, $run_id, $file) = @_;
	my ($meta, $tile, $rail, $marble) = $self->fetch_run_data($run_id);
	my $comments = $self->query_table('tile_id,comment', 'run_comment',
		"run_id=$run_id");
	# meta: id name digest date source person_id size_x size_y layers marbles
	#        0    1      2    3      4         5      6      7      8       9
	my $str = "Name $meta->[1]\n";
	$str .= "Date $meta->[3]\n" if $meta->[3];
	$str .= "Source $meta->[4]\n" if $meta->[4];
	$str .= "Author $self->{people}{$meta->[5]}\n" if $meta->[5];
	$str .= $meta->[10] if $meta->[10];
	my $name = $self->translate($meta->[1]);
	if ($meta->[4]) {
		$name .= " (" . loc($meta->[4]). ")";
	} elsif ($meta->[5]) {
		$name .= " (" . $self->{people}{$meta->[5]} . ")";
	}
	warn loc("Exporting %1\n", $name);
	$file = $self->get_file_name($file, '', loc("ENTER to write to STDOUT"));
	if ($file) {
		open F, ">$file" or die "$file: $!\n";
	} else {
		*F = *STDOUT;
	}
	print F $str;
	my $large = $meta->[6] > 35 or $meta->[7] > 35 ? 1 : 0;
	my ($dx, $dy) = (0, 0);

	my $bpos = '';
	my (%bt, %et, %wall, $nt, $detail);
	for my $t (@$tile) {
		my ($sym, $posx, $posy, $posz, $tdir) = @{$t}[2..6];
		if ($sym eq 'B' or $bpos eq "$posx,$posy") {
			$detail = $t->[7] if $sym eq 'B';
			$bpos = "$posx,$posy" if $sym eq 'B';
			push @{$bt{$detail}}, $t if $bpos;
		} else {
			$bpos = '';
			push @$nt, $t;
		}
	}
	for my $l (0 .. $meta->[8]) {
		# tile: id run_id element posx posy posz orient detail level
		#        0      1       2    3    4    5      6      7     8
		# handle transparent planes first
		if ($l) {
			my $tp = (grep {$_->[2] =~ /([=^])/ and $_->[8] == $l} @$tile)[0];
			my $pos = $self->num2pos($tp->[3], $tp->[4], 1);
			$pos =~ s/^([^\s]*) //;
			$pos = "$tp->[4],$tp->[3]" if $large;
			my $plane_pos = $1;
			my $mid = $tp->[2] eq '^' ? 3 : 2;
			say F "Level $l";
			say F "$pos $tp->[2]";
		}
		my $oldpos = 0;
		my $str = '';
		my $oldplane = '';
		my $comment = '';
		for my $t (@$nt) {
			next if $t->[8] != $l;
			my ($sym, $posx, $posy, $posz, $tdir, $detail) = @{$t}[2..7];
			next if $sym =~ /[=^]/ or ! $sym;
			my $pos = $self->num2pos($posx, $posy, 1);
			$pos = "$posy,$posx" if $large;
			if ($pos ne $oldpos) {
				say F "$str$comment" if $str;
				$oldpos = $pos;
				$comment = '' if $str;
				$str = "$pos ";
			}
			# strings without \n are inline comments, also in multiline
			if (exists $comments->{$t->[0]}) {
				if ($comments->{$t->[0]} !~ /\n$/) {
					$comments->{$t->[0]} =~ s/(.*)$//;
					$comment = $1;
				}
				print F $comments->{$t->[0]} if $comments->{$t->[0]};
			}
			$str .= $sym;
			# details given
			if ($detail) {
				$detail = '' if $sym eq 'E';
				# default for bridges
				$detail = '' if $sym eq 'xB' and $detail == 4;
				# angled bases for trampolin
				$detail =~ tr/0-5/a-f/ if $sym eq 'R';
				$str .= $detail if $detail;
			}
			$str .= chr(97 + $tdir) if $sym !~ /^[+\dL]/;
			# rail: rail dir tile1_id tile1_level tile2_id tile2_level detail
			#          0   1        2           3        4           5      6
			my @rails = grep {$t->[0] == $_->[2]} @$rail;
			for my $r (@rails) {
				$sym = $r->[0];
				# bridge is noted in detail only, not as a rail
				next if $sym eq 'xb';
				if ($sym =~ /x[sml]/) {
					my $wall = $r->[6] % 100;
					my $num_pillar = int($r->[6]/100);
					$num_pillar = '' if $num_pillar == 1;
					$wall{$wall} = "$r->[2]:$pos $num_pillar$sym"
						. chr(97 + $r->[1]);
				} else {
					$str .= " " . $sym . chr(97 + $r->[1]);
				}
			}
			# marble: tile_id orient color
			#               0      1     2
			for my $m (grep{$_->[0] == $t->[0]} @$marble) {
				$str .= ' o';
				$str .= $m->[2] if defined $m->[2];
				$str .= chr(97 + $m->[1]) if defined $m->[1];
			}
			$oldpos = 0 if $sym =~/^[a-w]/;
			if ($str =~s/^(\S+ )(E[^E]+)E//) {
				say F "$1$2";
				$str = "$1E";
			}
		}
		say F "$str$comment" if $str;
	}
	for my $w (sort {$a <=> $b} keys %wall) {
		my $tid = $1 if $wall{$w} =~ s/^(\d+)://;
		say F $wall{$w};
		my $str = '';
		for my $b ($bt{$w}) {
			for my $t (@$b) {
				my ($sym, $posx, $posy, $posz, $tdir, $detail) = @{$t}[2..7];
				$detail ||= '';
				if ($sym eq 'B') {
					say F $str if $str;
					my $pos = $self->num2pos($posx, $posy, 1);
					$pos =~ s/^([^\s]*) //;
					$pos = "$posy,$posx" if $large;
					my @res = grep {$_->[0] == $tid} @$tile;
					warn "ambiguity for tile $tid\n" if @res != 1;
					my $z_wall = $res[0]->[5] - 14;
					my $hole = ($posz - $z_wall)/2;
					$hole = chr(87 + $hole) if $hole > 9;
					$detail = int($detail/100) || '';
					$str = "$pos $detail${hole}B";
				} else {
					$str .= $sym;
					if ($detail) {
						# default for bridges
						$detail = '' if $sym eq 'xB' and $detail == 4;
						# angled bases for trampolin
						$detail =~ tr/0-5/a-f/ if $sym eq 'R';
						$str .= $detail if $detail;
					}
				}
				$str .= chr(97 + $tdir) if $sym !~ /^[+\dBL]/;
				my @rails = grep {$t->[0] == $_->[2]} @$rail;
				for my $r (@rails) {
					$sym = $r->[0];
					# bridge is noted in detail only, not as a rail
					next if $sym eq 'xb' or $sym =~ /^x[sml]/;
					$str .= " " . $sym . chr(97 + $r->[1]);
				}
			}
		}
		say F $str if $str;
	}
}

sub delete_run {
	my ($self, $id) = @_;
	my $dbh = $self->{dbh};
	my $runs = $self->query_table('id,name', 'run');
	my $yn = $self->prompt(loc("really delete '%1'", $runs->{$id}));
	my $Y = loc('Y');
	return '' if $yn !~ /^[y$Y]/i;
	my $res = $dbh->do("DELETE FROM run WHERE id=$id");
	if ($res == 1) {
		warn loc("Run %1 deleted\n", $runs->{$id});
	} else {
		die loc("No run with id %1 existing\n", $id);
	}
	$dbh->do("DELETE FROM run_tile WHERE run_id=$id");
	$dbh->do("DELETE FROM run_rail WHERE run_id=$id");
	$dbh->do("DELETE FROM run_marble WHERE run_id=$id");
	$dbh->do("DELETE FROM run_no_elements WHERE run_id=$id");
}

sub list_marble_runs {
	my ($self, $person_id, @args) = @_;
	my $elem_name = $self->{elem_name};
	$person_id = $self->owner_of_set_id() if ! $person_id;
	my $owned = $self->get_owned_elements($person_id);
	my ($caption, @ids);
	# loop over runs
	my $run_ids = $self->{run_ids};
	for my $k (sort {$run_ids->{$a} <=> $run_ids->{$b}} keys %$run_ids) {
		my $id = $run_ids->{$k};
		# get width and height of ground plane
		my $sql = "SELECT name,source,size_x,size_y,layers,person_id FROM run
			WHERE id=$id";
		my $res_meta = ($self->{dbh}->selectall_array($sql))[0];
		my ($name, $source, $size_x, $size_y, $layers, $author) = @$res_meta;
		my $bx = int(($size_x + 5)/6);
		my $by = int(($size_y + 4)/5);
		$name = $self->translate($name);
		if ($source) {
			$name .= " (" . loc($source). ")";
		} elsif ($author) {
			$name .= " (" . $self->{people}{$author} . ")";
		}
		# required elements for the run
		my $elems = $self->get_run_elements($id);
		my $skip = @args;
		for my $arg (@args) {
			my $ok = 1;
			for my $and_arg (split /,/, $arg) {
				# run number
				if ($arg =~ /^(\d+)$/) {
					$ok = 0 if $and_arg != $id;
				# board size nx*ny[*nz]
				} elsif ($and_arg =~ /^(\d+)x(\d+)(?:$|x(\d+))$/) {
					my ($x, $y, $z) = ($1, $2, $3);
					$ok = 0 if $x != $bx or $y != $by
							or (defined $z and $z != $layers);
				# element used in the run
				} elsif ($and_arg =~ /^[xyz]?.$/) {
					$ok = 0 if ! exists $elems->{$and_arg};
				# string (at least 3 chars) contained
				} elsif (length $and_arg > 2 and $name =~ /$and_arg/i) {
					$ok = 0 if $name !~ /$and_arg/i;
				}
			}
			$skip = 0 if $ok == 1;
		}
		next if $skip;
		# check if number of elements required are available if person known
		my $ok = loc('N');
		my $absent = $self->check_num_elements($elems, $owned);
		$ok = loc('Y') if $person_id and ! $absent;
		my $header = loc(" id OK x*y*z title (source)");
		my $vers = "gravi $Game::MarbleRun::VERSION";
		my $len = 80 - length($header) - length($vers);
		warn loc("List of registered marble runs"), "\n", '-' x 80, "\n",
			$header, ' ' x $len, $vers, "\n", '-' x 80, "\n" if ! $caption++;
		push @ids, $id;
		printf STDERR "%3d %2s%2dx%1dx%1d %s\n",
			$id, $ok, $by, $bx, $layers, $name;
		if ($self->{verbose}) {
			$self->print_items($elems, 'elem_name');
			print "\t", loc("missing"), ": $absent->{$_} x ",
				loc($elem_name->{$_}), "\n" for keys %$absent;
		}
	}
	return @ids;
}

sub inventory {
	my ($self, $id) = @_;
	return if ! $id;
	my $set = $self->query_table('set_id,count', 'person_set', "person_id=$id");
	$self->print_items($set, 'set_name');
	$self->print_items($self->get_owned_elements($id), 'elem_name');
}

sub print_items {
	my ($self, $num, $what) = @_;
	print loc("Number of owned sets\n") if $what eq 'set_name';
	print loc("Number of owned elements\n") if $what eq 'elem_name';
	my @id = $self->{verbose} ? sort {$num->{$b}<=>$num->{$a}} keys %$num : sort keys %$num;
	# multi column output depending on width of names to be printed
	my @width = (0, 0, 0);
	my $i = 0;
	for (@id) {
		my $len = length loc($self->{$what}{$_});
		$width[$i] = $len if $len > $width[$i];
		$i = ++$i % 3;
	}
	my $cols = $width[0] + $width[1] + $width[2] +21 > 80 ? 2 : 3;
	my $fmt = "%3s %2s %$width[0]s%s";
	$i = 0;
	my @sep = ('', '', "\n");
	for (@id) {
		printf("%3s %2s %$width[$i]s%s", $num->{$_}, $what eq 'set_name' ? '' : $_,
			adjust(loc($self->{$what}{$_}), $width[$i]), $sep[$i]);
		$i = ++$i % 3;
	}
	print "\n" if ($i - 1) % $cols;
}

sub translate {
	my ($self, $str) = @_;
	return if ! $str;
	for ('track', 'run', values %{$self->{set_name}}) {
		next if ! $str =~ /$_/i;
		my $trans_str = loc(lc $_);
		# try original string if lower cased string does not match
		$trans_str = loc($_) if $trans_str eq lc $_;
		$str =~ s/$_/$trans_str/i;
	}
	return $str;
}

sub find_balcony_dir {
	my ($self, $x1, $y1, $o, $x2, $y2) = @_;
	#print "x,y,dir=$x1, $y1, $o, xb,yb=$x2, $y2\n";
	my $dir = 0;
	if ($o == 0 or $o == 3) {
		$dir = $x1 < $x2 ? 4 : 1;
	} elsif ($o == 1 or $o == 4) {
		$dir = 2*($y1 - $y2) < ($x2 -$x1) ? 5 : 2;
	} elsif ($o == 2 or $o == 5) {
		$dir = 2*($y2 - $y1) > ($x2 -$x1) ? 0 : 3;
	}
	#print "o=$o dir=$dir\n";
	return $dir;
}

sub find_dir {
	my ($self, $x1, $y1, $x2, $y2) = @_;
	my $dir = 0;
	for ($dir = 0; $dir < 6; $dir++) {
		my ($x, $y) = $self->to_position($x1, $y1, $dir, 1);
		return $dir if ($x == $x2) and ($y == $y2);
	}
	$self->error("Field (%1, %2) is not adjacent to (%3, %4)", $x2, $y2, $x1, $y1);
	return 0;
}

sub to_position {
	my ($self, $x1, $y1, $dir, $len) = @_;
	my ($x2, $y2) = ($x1, $y1);
	return ($x2, $y2) if ! defined $dir or $dir eq 'M' or ! $len;
	$dir = $dir % 6;
	# bent rails
	if ($len =~ /[+-]/) {
		my $dx = [1, 2, 1, -1, -2, -1];
		my $dy = [-1, 0, 2, 2, 0, -1];
		$dir = ($dir + 5) % 6 if $len eq '2-';
		$x2 += $dx->[$dir];
		$y2 += $dy->[$dir];
		$y2 -- if ($x1 % 2) and $dy->[$dir];
		return ($x2, $y2);
	}
	my $sign_y = (($dir + 1) % 6) < 3 ? -1 : 1;
	if ( ($dir % 3) == 0) {
		$y2 += $sign_y*$len;
	} else {
		$x2 += $dir < 3 ? $len : -$len;
		my $inc = (2*($x1 % 2) - 1 + $sign_y) ? 0 : 1;
		$y2 += $sign_y*int(($len + $inc)/2);
	}
	return ($x2, $y2);
}

sub dir_string {
	my ($self, $dir, $alternate_string) = @_;
	my $str = $alternate_string ? loc('Direction') : loc('Orientation');
	return '' if ! defined $dir;
	$dir %= 6;
	# "\x{2191}","\x{2197}","\x{2198}","\x{2193}","\x{2199}","\x{2196}"
	return "$str $self->{dirchr}[$dir] (" . chr($dir + 97) . ")";
}

sub display_run {
	my ($self, $run_id, $file) = @_;
	my $quiet = $self->{quiet};
	my $svg = $self->{svg};
	my %pos;
	my $tp_pos = [[0,0]];
	my ($meta, $tile, $rail, $marble, $excl) = $self->fetch_run_data($run_id);

	# meta: id name digest date source person_id size_x size_y layers marble
	#       0  1    2      3    4      5         6      7      8      9
	my $bx = int(($meta->[6] + 5)/6);
	my $by = int(($meta->[7] + 4)/5);
	$self->error("Unknown board size, exiting") if ! $bx or ! $by;
	$self->{relative} = 1 if $meta->[6] > 35 or $meta->[7] > 35;
	my ($dx, $dy) = (0, 0);

	say loc("Instructions for %1, board size %2",
		$self->translate($meta->[1]), "${by}x$bx") if ! $quiet;

	# SVG #
	if ($svg) {
		# ask for SVG output
		$self->{outputfile} = $self->get_file_name($self->{outputfile}, 'svg',
			loc("ENTER to continue without SVG output"), 1)
			if ! $self->{outputfile};
			$self->{outputfile} = undef if ! $self->{outputfile};
		$self->board($by, $bx, $run_id, $self->{fill}, $excl, $meta->[1]);
	}
	# SVG end #

	# sort tiles and rails based on ground plane numbers first column, then row
	# then balconies with increasing z
	if ($self->{relative}) {
		@$tile = sort {$a->[8] <=> $b->[8] ||
			int(($a->[3] + 5)/6) <=> int(($b->[3] + 5)/6) ||
			int(($a->[4] + 4)/5) <=> int(($b->[4] + 4)/5) ||
			$a->[3] <=> $b->[3] || $a->[4] <=> $b->[4] ||
			$a->[5] <=> $b->[5]} @$tile;
		@$rail = sort {$a->[3] <=> $b->[2] ||
			int(($tile->[$a->[2]][3]+5)/6) <=> int(($tile->[$b->[2]][3]+5)/6) ||
			int(($tile->[$a->[2]][4]+4)/5) <=> int(($tile->[$b->[2]][4]+4)/5) ||
			$tile->[$a->[2]][3] <=> $tile->[$b->[2]][3] ||
			$tile->[$a->[2]][4] <=> $tile->[$b->[2]][4]} @$rail;
	} else {
		@$tile = sort {$a->[8] <=> $b->[8] ||
			$a->[3] <=> $b->[3] || $a->[4] <=> $b->[4] ||
			$a->[5] <=> $b->[5]} @$tile;
		@$rail = sort {$a->[3] <=> $b->[2] ||
			$tile->[$a->[2]][3] <=> $tile->[$b->[2]][3] ||
			$tile->[$a->[2]][4] <=> $tile->[$b->[2]][4]} @$rail;
	}
	# calculate marble path
	my ($marbles, $no_marbles) = $self->do_run($run_id);
	for my $l (0 .. $meta->[8]) {
		# handle transparent planes first
		if ($l) {
			my $tp = (grep {$_->[2] =~ /([=^])/ and $_->[8] == $l} @$tile)[0];
			if (! $tp) { # should not happen
				$self->error("Incomplete data for level %1, skipping it", $l);
				next;
			}
			my $tp_type = $tp->[2];
			my ($tp_x, $tp_y) = ($tp->[3], $tp->[4]);
			my $pos = $self->num2pos($tp_x, $tp_y);
			my $mid = $tp_type eq '^' ? 3 : 2;
			if ($self->{relative}) {
				$dx = $tp_x - $mid;
				$dy = $tp_y - $mid;
				$tp_pos->[$l] = [$dx, $dy];
			}
			say loc("Place %1 %2 with center at %3",
				lcfirst loc($self->{elem_name}{$tp->[2]}),$l,$pos) if ! $quiet;
			# SVG #
			$self->draw_tile(@{$tp}[2..7]) if $svg;
			# SVG end #
		}
		# tile: id run_id element x y z orient detail level
		#        0      1       2 3 4 5      6     7      8
		# first pass: no balconies, but walls, second pass balconies and rails
		for my $pass (1, 2) {
			my $str;
			my $num = 0;
			my $balcony_pos = 0;
			for (my $i =0; $i < @$tile; $i++) {
				next if $tile->[$i][8] != $l;
				my ($id, $sym, $x, $y, $z, $tdir, $detail) =
					@{$tile->[$i]}[0,2..7];
				undef $tdir if $sym =~ /^L|^\+\d/;
				# transparent planes already handled
				next if $sym =~ /[=^]/ or ! $sym;
				# double balcony on height element in 1st pass, other end in 2nd
				next if $sym eq 'E' and ! $detail and $pass == 2;
				# remember tile_id
				$pos{$id} = $tile->[$i];
				my $pos = loc("At %1", $self->num2pos($x, $y));
				$pos = loc('At %1', loc('Level') . " $l ") . loc('pos') . ' '
					. ($y - $dy) . ($x - $dx) if $l and $self->{relative};
				if ($str) {
					$str .= ', ' if ! $num;
				} else {
					$str = "$pos ";
				}
				if ($sym eq 'B' or ($sym eq 'E' and $tile->[$i][7])) {
					$balcony_pos = $pos;
					$str = '';
					$str = "$pos " if $pass == 2;
					next if $pass == 1;
				} else {
					# elements on balconies get treated in 2nd pass
					if ($pass == 1 and $pos eq $balcony_pos) {
						$str = '', $balcony_pos = 0 if $sym !~ /\d+|^[+BEOR]/;
						next;
					} elsif ($pass == 2 and $pos ne $balcony_pos) {
						$str = '', $balcony_pos = 0 if $sym !~ /\d+|^[+BEOR]/;
						next;
					}
				}
				# accumulate height elements
				if ($sym =~ /^[+L\d]/) {
					if ($sym =~ /^[\d]/) {
						$num += $sym;
						$sym = 1;
						# next tile at same position of same kind ?
					next if defined $tile->[$i+1] and $tile->[$i+1][2] =~ /\d/
						and $tile->[$i+1][3] == $x and $tile->[$i+1][4] == $y
						and $tile->[$i+1][8] == $l;
					} elsif ($sym =~ /^[+L]/) {
						$num++;
					next if defined $tile->[$i+1] and $tile->[$i+1][2] eq $sym
						and $tile->[$i+1][3] == $x and $tile->[$i+1][4] == $y
						and $tile->[$i+1][8] == $l;
					}
					$str .= "$num x " if $num > 1;
					$num = 0;
				}
				my $elem = $self->{elem_name}{$sym};
				$str .= loc('On ') if $sym eq 'E' and $tile->[$i][7];
				$str .= loc($elem) if $sym and $elem;
				# handle details (or defaults) and balconies
				if ($detail or $sym =~ /^x[BH]|^B/) {
					$str .= ' ';
					if ($sym eq 'xB') {
						$str .= loc("with %1 bridge elements", $detail || 4);
					} elsif ($sym eq 'xH') {
						$str .= loc("with %1 green parts", $detail || 2);
					} elsif ($sym eq 'xF') {
						my $num = $detail =~ /(\d+)/ ? $1 : 2;
						my $dir = ($detail =~ /([a-f])/) ? ord($1)-97 : $tdir+3;
						$str .= loc("with %1 transparent parts", $num) . ' ';
						$str .= loc("outlet in %1", $self->dir_string($dir, 1));
					} elsif ($sym eq 'R') {
						my $trampolin = loc($elem);
						$str =~ s/\s*$trampolin\s*//;
						for (split '', $detail) {
							$str .= ' ' . loc($self->{elem_name}{'r'}) . ' '
							. $self->dir_string($detail) . ', ';
						}
						$str .= $trampolin;
					} elsif ($sym eq 'E') {
						$str .= "($detail)" if $detail;
					} elsif ($sym eq 'B') {
						my @res = grep {$_->[0] =~ /^x[sml]/ and (($_->[6] % 100) || -1) == $detail} @$rail;
						$self->error("### Spurious bug in 'display run',exiting. Please rerun program") if ! @res;
						$detail %= 100;
						warn $#res, " ambiguity for wall $detail\n" if @res > 1;
						my $tid = $res[0]->[2];
						@res = grep {$_->[0] == $tid} @$tile;
						warn "ambiguity for tile $tid\n" if @res > 1;
						my $z_w = $res[0]->[5] - 14;
						my $hole = ($z - $z_w)/2;
						#print "### wall $detail tid=$tid, zb=$z, zw=$z_w hole $hole\n";
						$str .= loc("in wall %1 hole %2", $detail, $hole);
					}
				}
				undef $tdir if $sym eq '+';
				$str .= ' ' . $self->dir_string($tdir) if defined $tdir;
				# collect tiles at the same position and print only one line
				if (! defined $tile->[$i+1] or $tile->[$i+1][3] != $x
						or $tile->[$i+1][4] != $y or $tile->[$i+1][2] eq 'B'
						or $l ne $tile->[$i+1][8] or ($tile->[$i+1][2] eq 'E'
						and $tile->[$i+1][7])) {
					print "$str\n" if ! $quiet;
					$str = '';
					$num = 0;
				}

				# SVG #
				# double balcony already drawn in 1st pass
				#print "tile $sym, dir $tdir detail $detail\n";
				next if $sym eq 'E' and $detail;
				# get marbles for that tile
				my $ball = [grep {$_->[0] == $id} @$marble];
				$self->draw_tile($sym, $x, $y, $z, $tdir, $detail, $ball) if $svg;
				# SVG end #
			}
			# rail placement: rail direction t1_id t1_level t2_id t2_level
			#                    0         1     2        3     4        5
			for my $r (@$rail) {
				my $sym = $r->[0];
				next if $sym =~ /x[sml]/ and $pass == 2;
				next if $sym !~ /x[sml]/ and $pass == 1;
				next if $r->[3] > $l or $r->[5] > $l;
				next if $r->[3] < $l and $r->[5] < $l;
				my $dir = $r->[1];
				my ($x1, $y1) = @{$pos{$r->[2]}}[3,4];
				my ($x2, $y2) = @{$pos{$r->[4]}}[3,4];
				if ($sym =~ /x[sml]/) {
					my $len = $sym eq 'xs' ? 2 : $sym eq 'xm' ? 3 : 4;
					($x1, $y1) = $self->to_position($x2, $y2, ($r->[1]+3)%6, $len);
				}
				my $pos1 = $self->num2pos($x1, $y1);
				my $pos2 = $self->num2pos($x2, $y2);
				if ($self->{relative}) {
					if ($r->[3]) {
						$pos1 = loc('Level') . " $l " . loc('pos')
						. ' ' . ($y1 - $dy) . ($x1 - $dx);
					}
					if ($r->[5]) {
						$pos2 = loc('Level') . " $l " . loc('pos')
						. ' ' . ($y2 - $dy) . ($x2 - $dx);
					}
				}
				my $name = loc($self->{elem_name}{$sym});
				# bridge already described in xB tile
				if ($sym =~ /^x[sml]/) {
					my $pillar = int($r->[6]/100) || 1;
					my $wall = $r->[6] % 100;
					$name =~ s/ / $wall /;
					say loc("From pillar %1 at %2 to %3 %4", $pillar,$pos1,
						$pos2, $name, $self->dir_string($dir, 1)) if ! $quiet;
				} else {
					say loc("From %1 to %2 %3 %4", $pos1, $pos2, $name,
					$self->dir_string($dir, 1)) if $sym ne 'xb' and ! $quiet;
				}
				# SVG #
			# for the rail we do need the opposite direction
				my $dir2 = $r->[6];
				$self->draw_rail($sym, $x2, $y2, $x1, $y1, $dir, $dir2) if $svg;
				# SVG end #
			}
		}
		# show intermediate steps and display marbles if not animated
		if ($svg and $l != $meta->[8]) {
			$self->display_init_balls($marbles, $l) if ! $self->{motion};
			$self->emit_svg($file, $l);
		}
	}
	# do not display marbles that cannot start
	$self->display_balls($marbles);
	$self->emit_svg($file, '');
	#$marble->[$_] = undef for @$no_marbles;
	$self->initial_actions($tile, $marbles, $tp_pos);
}

sub initial_actions {
	my ($self, $tile, $marble, $dxy) = @_;
	# marble placement and initial actions
	my %m;
	push @{$m{$_->[0]}}, [$_->[1], $_->[2]] for grep {$_} @$marble;
	my $ball = loc($self->{elem_name}{'o'});
	for my $t (@$tile) {
		# tiles with initial states: start, (tunnel)switch, cannon, flip,
		# hammer, jumper, cascade,vvolcan, splash, lift, catapult, bridge,
		# zipline, tiptube, mixer, transfer, splitter, turntable
		next if $t->[2] !~ /^[ASUMFHJKNP]$|^x[FKBASTMR]$|^y[ST]$/;
		my ($id, $sym, $x, $y, $dir, $detail, $l) = @{$t}[0,2,3,4,6,7,8];
		# bridges can unfold with 2 elements only
		next if $sym eq 'xB' and $detail != 2;
		my $elem = $self->{elem_name}{$sym};
		my $pos = loc("At %1", $self->num2pos($x, $y));
		$pos = loc('At %1', loc('Level') . " $l ") . loc('pos') . ' '
			. ($y - $dxy->[$l][1]) . ($x - $dxy->[$l][0]) if $l and $self->{relative};
				$pos .= ' (' . loc($elem) . ') ' if $sym;
		# symbols where marbles can start
		if ($sym =~ /^[AMNP]$|x[AFST]/) {
			next if ! exists $m{$id};
			my ($count, $marbles);
			# combine repeated marble string (can compare undef values)
			my $m0 = $m{$id}->[0];
			for (@{$m{$id}}) {
				no warnings;
				$count++ if $_->[0] eq $m0->[0] and $_->[1] eq $m0->[1];
				use warnings;
				next if $count > 1;
				$marbles .= ', ' if $marbles;
				$marbles .= "$self->{color}{$_->[1]||'S'} $ball";
				$marbles .= ' ' . $self->dir_string($_->[0]) if defined $_->[0];
			}
			$pos .= ($count ? "$count x " : '') . $marbles;
		} elsif ($sym eq 'S' or $sym eq 'U') {
			next if ! $detail;
			$pos .= loc("Switch state") . " $detail";
		} elsif ($sym =~ /^[FHJKN]$|x[KBR]/) {
			$pos .= loc('prepare for start');
		} elsif ($sym eq 'yS') {
			$pos .= loc("flap in %1", $self->dir_string($dir, 1));
		} elsif ($sym eq 'xM') {
			next if ! defined $detail;
			$pos .= loc("%1 should leave tile in %2", $ball,
				$self->dir_string($detail, 1));
		} elsif ($sym eq 'yT') {
			next if ! $detail;
			$pos .= loc("Turntable rotor position") . " $detail";
		}
		say $pos;
	}
}
1;
__END__
=encoding utf-8
=head1 NAME

Game::MarbleRun - Manage marble runs

=head1 SYNOPSIS

  #!/usr/bin/perl
  use Game::MarbleRun;
  $g = Game::MarbleRun->new();
  $g->list_elements();
  $g->list_sets();
  $g->inventory();
  $g->list_marble_runs();
  # need to have stored runs and provide an existing run id
  $g->export_marble_run($id);
  $g->display_run($id);

=head1 DESCRIPTION

Game::MarbleRun provides methods to display the contents of a gravitrax
database such as showing the names of available elements or printing
instructions to build a stored track. If in addition a SVG file of a stored
tracks should be generated, Game::MarbleRun::Draw has to be used instead.

To store data in the DB like owned material and descriptions of marble runs
methods from Game::MarbleRun::Store have to be used.

=head1 DESCRIPTION OF THE INPUT FORMAT

=head2 NAMES IN THE INPUT FILES

The program gravi is localized. All building set names and header keywords
as well as the word 'level' can be entered in English or in the used language,
provided the translations are done. The case can be freely chosen.
Currently only German besides English is fully supported.

=head2 OWNED MATERIAL

To describe what GraviTrax® elements someone has, the following notation
is used:

Owner <Owner Name> [*]
<count> <Construction Set Name|Element Character>

The first line has to be an owner line, then one or more material lines can
follow. The construction set names can be obtained by the command

  gravi -s

At least one starter set name must be present. Other names than the starter
sets can be abbreviated to a minimum of two characters as long as the string
still uniquely identifies the set. Sample line: '2 Hamm'

Additional or missing elements can also be entered, where the number of
elements can be positive or negative and the elements are named by its
1 or 2 character symbols. The list of element names and its identifying chars
can be obtained by the command.

  gravi -e

Information on separate lines can be joined using a semicolon as separator
character. Empty lines and comments (starting with #) are skipped.

If material for several users is registered, by default the material from the
first user is the one used in the program. It can be overwritten temporarily
by calling gravi with the -u flag or with an owner line containing a '*'.
If multiple owner lines with a star (*) exist, the last one entered is used.

=head2 MARBLE TRACKS

A marble track definition starts with a header block. The name of the marble
run has to be the contents of the first line or be given in a Name line. Other
lines as Date, Author and Source lines are optional. Lines starting with #
(comment lines) are copied as is into the DB and empty lines are ignored.
A complete header block looks as follows:

  Name <name of the track>
  Date <free form date>
  Author <person name>
  Source <source of the track>

Such a given header block uniquely identifies a marble track. Any change there
is seen as a new track while changing other lines does not affect the
identification of a track.

The subsequent lines describe the placement of tiles, rails and marbles on the
board. Several lines can be joined by using a semicolon as a delimiter.

A complete line looks as follows

<position> <height><tile><detail><orientation> <rail><direction> <marbles>

For walls (which are treated as rails) a <detail> field is possible as well.

=head3 Position

The position is either a relative position on a plate <row><column> or an
absolute position by numbering all rows and columns from [1..9a-z]. Absolute
position numbering can hence be used only for runs with less than 36 rows
or columns.

If the description starts with a base plate line, relative coordinates are
used, if such lines are missing then the positions 1..z are used.

=head3 Base plates

Base plate lines (starting with _) are written in the form

_ <column> <row>

Then the positions are relative to the left upper edges of a plate, which has
the position 11. Therefore for positions only digits up to 6 are possible.

A picture of the xy positions on an 1,2 board is contained in the gravi_en.pdf
document and can also be generated by the simple program

  #!/usr/bin/perl
  use Game::MarbleRun::Draw;
  my $g = Game::MarbleRun::Draw->new();
  $g->board(1, 2);        # size in horizontal, vertical direction
  $g->emit_svg('board');  # a file board.svg gets written

=head3 Height

<height> is an optional string of joined height tile symbols (gray tiles: 1,
black tiles: +, more from the vertical starter set, see below). The string
can be shortened by adding the heights where one gray or 2 black tiles
represent a height of 1. Thus 111+++ can be shorter written as 4+.

=head3 Tiles

The <tile> is a one or two character symbol for a tile. The list of element
names and its identifying chars can be obtained by the command

  gravi -e

=head3 Transparent planes

The transparent plane is noted like any other tile with its center as
the position, but no height and no orientation information is needed.
The height gets calculated from the tiles underneath. Descriptions for
tiles on the transparent plane may follow only after the description line
for the transparent plane. This restriction can be circumvented by a line
of the form 'Level <n>' where n is a sequence number for transparent planes.
After such a line the tiles on that level (plane) may follow. If the relative
notation of positions is used then all positions on a transparent plane are
relative to the center, which has the position 3,3. For the absolute
position notation all positions are the ones on the ground plane.

=head3 Orientation

The <orientation> of a tile is given by letters a..f where a is the orientation
pointing north (up, 12 o clock) and the other ones are clockwise labeled b..f.
In the GraviTrax® starter set booklet most of the elements are displayed.
Orientation a is always the one where the front side of the element (south
west in the drawings) is pointing north. (except for launch pad, that is b).
An svg image of element orientations can also be generated by

  #!/usr/bin/perl
  use Game::MarbleRun::Draw;
  my $g = Game::MarbleRun::Draw->new();
  $g->orientations();
  $g->emit_svg('orient');

Some of the tiles and walls may need additional information to describe them.
In such cases <detail> information needs to be added (see below).

=head3 Rails and Walls

The next information in the line is on rails (and walls). The <rail> type
and the <direction> have to be entered. The starting point is the tile
described on the same line and the direction is counting clockwise from
a..f away from the starting point. Up to three rail descriptions are
possible. The vertical starter set adds walls, which are also noted as
rails, as they are connections between tiles. Up to 3 walls can be
attached to a tile in addition. For walls a <detail> between the symbol
name and the orientation character can be put. It is the pillar number
if the wall is not starting at the pillar closest to the ground plane.

=head3 Marbles

The last information is on <marbles>. Up to three marbles can be described
for a tile (exception lifter, there is no restriction. The information
starts with an 'o' (the marble type) followed by an optional
color [RGBSA] (red, green, blue, silver, gold) and an optional orientation.

=head3 Exceptions

There are a few exceptions to completely characterize an element:

The transparent plane and height tiles without other tiles on top do not
need an orientation char. For tunnel pillars however, which are height
tiles as well, an orientation has to be given.

The position of the transparent plane is always the location of its center
on the ground plane.

The open basket (O) (from the tunnel set) does not have height and
orientation information, it is entered with its position and the O only.

=head3 Detail

For switches (S) and tunnel switches (U) the initial switch position can
be indicated by a <detail> + or -, where + means, the switch lever arm
is turned clockwise.

For bridges (xB) the number of movable bridge elements used (an even
number) can be noted as detail after the 'xB'. If missing, 4 elements
are assumed.

For spirals (xH) the number of green elements (including start and end
element) should be given as detail after the xH. The orientation is
given by the direction of the end element (the low one). The direction of
incoming marbles is calculated from the number of green spiral elements,

For a lifter (xL) the number of transparent elements (including in and out
element) and the orientation of the in element should be given as detail
after the xL. The orientation is given by the direction of the end element
(the low one).

Angled tiles under a trampoline (R) are noted as detail after the R.
Only the orientation(s) a-f of the angled tiles have to be given.

=head3 Balconies

The vertical starter set introduces two types of balconies. Both act as
height elements and get noted together with other height elements. Simple
balconies arre attached to holes in the transparent walls. The hole number
is coded as 1..9a..d for holes 1 .. 13. It has to be prepended to the symbol
B for the balcony followed by the orientation character. If there are more
walls on top of each other then for a balcony on a higher wall the (lower)
pillar number for the pillar, where the wall is attached to, has to be
added as a detail to the balcony description.

Double balconies have two positions and need to get registered with these
positions twice. The first position is that in a stack of height elements.
The double balcony has to be noted there with its orientation together
with the other height elements. Then on a separate line the second position
has to be written down, followed by the symbol E and the orientation again.
The elements on top of the balcony (height tiles, another tile and rails)
are noted afterwards. If more than one double balcony is used in a stack
of height elements, its sequence number counted from bottom has to be
inserted as a detail on this (second) line.
For examples of this notation see the included sample runs in the test
directory t/data.

=head1 METHODS

=head2 new (constructor)

$g = Game::MarbleRun->new(%attr);

Creates a new game object and initializes a sqlite database if not yet
existing. By default the DB is located at ~/.gravi.db in the callers home
directory. The DB is populated initially with information on GraviTrax®
construction sets and elements. The following attrs can be used:

  verbose => 1               sets verbosity
  db      => "<file name>"   alternate name and place of the DB

=head2 config

$g->config($db);

Initialises the db at location $db if not yet done by calling connect_db.
Prefetches some often used values from the DB.

=head2 connect_db

$dbh = $g->connect_db($db);

Connects to the DB at $db. Populates elements and sets tables by calling
create_tables if not yet done. Returns the database handle or undef on error.

=head2 create_tables

$g->create_tables($dbh);

Creates the table structure and populates elements and sets if not existing.

=head2 finish

$g->finish();

disconnects the DB

=head2 list_elements

$g->list_elements();

lists the distinct elements available in GraviTrax® and its symbol names.

=head2 list_sets

$g->list_sets(@args);

lists the known construction sets from GraviTrax® with its internal id.
In verbose mode (if $g->{verbose} is set) the elements in the sets are
listed as well. If arguments are given, sets are selected according to
the arguments and its contents is displayed. Valid arguments are the
displayed set id, an (abbreviated) set name or an element name (then
sets are listed, where this element is contained).

=head2 get_run_elements

$num = $g->get_run_elements($run_id);

returns a hashref containing the number of elements (values) to build a track
identified by its run_id and the corresponding element symbols (keys)

=head2 get_owned_elements

$owned = $g->get_owned_elements($person_id);

returns a hashref containing the number of elements (values) that a person
(identified by its person_id) possesses and the corresponding elements (keys).
If the id is not given or no person with that id is known, the elements from
the starter set are returned.

=head2 check_num_elements

$missing = $g->check_num_elements($needed, $owned);

compare the number of elements required to build a track with the number of
owned elements. A hashref with the number and kind of missing elements is
returned or undef if all needed elements are available.

=head2 owner_of_set_id

$id = $g->owner_of_set_id($string);

If the string is not given, the id of the main user (stored in the DB) is
returned. If the string is an existing user_id or the string uniquely
identifies a user then the user_id is returned. Otherwise a list of person
names and its ids is printed and an id is requested. Returns the person id.

=head2 export_marble_run

$g->export_marble_run($run_id, $filename);

converts the information for a marble run stored in the DB into a notation
that is used for describing marble runs. The result is written to a file (or
STDOUT if no filename is given). The notation used is described above and in
more detail in the document gravi_de.pdf (german only).

=head2 delete_run

$g->delete_run(run_id);

deletes the marble run given by its id from the DB.

=head2 list_marble_runs

@ids = $g->list_marble_runs($person_id, @args);

produce a short table with marble runs stored in the DB. In the table the
run id, the name of the run, its possible source and the board size is
printed. It is checked whether the owned material (or the material from the
starter set, if no id is given) is sufficient to build the run (indicated
by Y or N in the table). The @args are for producing a filtered list of runs.
Both run ids, element chars, strings from the description and an OK can
be used to filter the output. Only one condition must be met, if multiple
args are given

=head2 inventory

$g->inventory($person_id);

print the list of construction sets and the sum of different elements owned
by a given person.

=head2 display_run

$g->display_run($run_id, $file_prefix);

display human readable instructions to set up a marble run given by its id.
The file prefix is only used if called from Game::MarbleRun::Draw to output
a file_prefix.svg file.

=head1 HELPER METHODS

=head2 query table

$href = $g->query_table('var1,var2', 'table', 'condition');

returns a hashref of the query results from table with columns var1 and
var2, where var1 values are the keys, var2 the values of the resulting
hashref. Optionally a condition may be given.

=head2 prompt

$answer = $g->prompt($string);

print a string, read from STDIN and return 'n' unless the input contains [ynYN]
The answer is kept in $g->{answer}. Returns in subsequent calls without
reading from STDIN if the answer was Y or N (or its localized forms).

=head2 num2pos

$str = $g->num2pos($x, $y, $plain);

converts integer positions x,y to a string describing the position x,y.
The string depends on the setting of $g->{relative} and the maximum size
of the board. '??' is returned on error. With $plain set a shorter string
is returned.

=head2 error

$g->error($loc_string, @args);

prints a localized warning string (loc($loc_string, @args)). Dies with an error if the string contains quit or exit. A file name and line number is printed as
well if $g->{fname} and $g->{line} is set.

=head2 adjust

$padded_locstr = adjust($str, $width);

converts str to its localized form and appends required spaces to form a
string of length 'width'.

=head2 get_id

$id = $g->get_id($string, $id);

After having printed a list of items with its ids, print string and ask for
entering an id. Returns undef if the id is not purely integer.

=head2 fetch_run_data

($meta, $tile, $rail, $marble) = $g->fetch_run_data($run_id);

returns data structures containing information for a track identified by its id.
The following data are stored:

 meta: id name digest date src person_id sizex sizey layers marbles
        0    1      2    3   4         5     6     7      8       9
 tile: id run_id element posx posy posz orient detail level
        0      1       2    3    4    5      6      7     8
 rail: rail direction, tile1_id tile1_level tile2_id tile2_level
          0         1         2           3        4           5

=head2 get_file_name

my $filename = $g->get_file_name($name, $ext, $str);

output $str on STDOUT if not empty to ask for a file name. If name or ext
is given, only the missing piece needs to be entered. Checks for existing
files and requires confirmation to overwrite files.

=head2 print_items

$g->print_items($num, $what);

helper method to print a long string of element or set names and its count contained
in the $num hashref

=head2 find_balcony_dir

$dir = find_balcony_dir($x_pile, $y_pile, $orient, $x_balcony, $y_balcony);

For a pile at $x_pile, $y_pile where a wall is connected to and its direction
$orient, the direction of the balcony for a given $x/y_balcony is calculated.

=head2 translate($string)

$translated = $g->translate($string);

Looks for names of construction sets as defined in the DB as well as for the
strings 'track' and 'run' in the string and replaces them with its translation,
if provided in a <lang>/msg.po file

=head2 to_position($x1, $y1, $dir, $len)

($x2, $y2) = $g->to_position($x1, $y1, $dir, $len);

calculates the end point $x2, $y2 of a rail starting at position $x1, $y1 in
direction $dir with length $len. Bent rails of length 2 noted with
$len = '2+' (ball rolling clockwise) and '2-' (anti-clockwise) are covered
as well.

=head2 dir_string

$str = $g->dir_string($dir, $flag);

returns a localized string and a direction char for a given direction dir.
The word orientation instead of direction is used, if the flag is set.

=head2 initial_actions

$g->initial_actions($tile, $marble, $dxy);

prints initial actions such as placing marbles and engaging one time
action tiles. Requires cached data from display_run.

=head1 SEE ALSO

See also the documentation in Game::MarbleRun::Store and Game::MarbleRun::Draw.
The file gravi_en.pdf and gravi_de.pdf (in german) describe in more detail
the notation of marble runs understood by Game::MarbleRun::Store.

=head1 AUTHOR

Wolfgang Friebel, E<lt>wp.friebel@gmail.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2020-2025 by Wolfgang Friebel

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.28.1 or,
at your option, any later version of Perl 5 you may have available.

=cut

package Game::MarbleRun::Store;
$Game::MarbleRun::Store::VERSION = $Game::MarbleRun::VERSION;

use v5.14;
use strict;
use warnings;
use parent 'Game::MarbleRun';
use Game::MarbleRun::Draw;
use Game::MarbleRun::I18N;
use Locale::Maketext::Simple (Style => 'gettext', Class => 'Game::MarbleRun');
use Digest::MD5 qw(md5_base64);

sub new {
	my ($class, %attr) = @_;
	my $self = {
		verbose => $attr{verbose} || 0,
		db => $attr{db} || $Game::MarbleRun::DB_FILE,
	};
	bless $self => $class;
	$self->config();
}

sub process_input {
	my ($self, $file) = @_;
	my ($what, $rules, $run, $material);
	# store file content and determine if material or run files given
	$self->{warn} = 0;
	$self->{fname} = $file || 'STDIN';
	if ($file) {
		open F, $file or die "$file: $!\n";
		$self->error("File size too large, exiting") if -s $file > 100000;
	} else {
		*F = *STDIN;
	}
	{
		local $/ = '';
		$self->{file_content} = <F>;
	}
	close F if $file;
	return if ! $self->{file_content};
	print $self->{file_content} if $self->{verbose};
	$what = 'run';
	my $l_name = loc('Starter Set');
	if ($self->{file_content} =~ /(^|;)\s*\d+\s*x?\s+(XXL|$l_name|Starter)/mi) {
		my $rules = $self->parse_material($self->{file_content});
		$self->store_material($rules);
	} else {
		my $rules = $self->parse_run($self->{file_content});
		$self->store_run($rules);
	}
	return $self->{warn};
}

sub find_to_tile {
	# r: from_id x1 y1 z1 detail orient from_level, x2, y2, rail_id, dir wall
	#          0  1  2  3      4      5          6   7   8        9   10   11
	my ($self, $rail, $seen) = @_;
	my ($tile, $xf, $yf, $z, $d0, $d1, $l, $x, $y, $r, $dir, $wall) = @$rail;
	# finish line does not end on a tile
	return undef if $r eq 'e';
	my @ids = grep {! $self->no_rail_connection($_->[1]) and
		$_->[2] == $x and $_->[3] == $y} sort {$b->[4] <=> $a->[4]} @$seen;
	if ($r =~ /x[sml]/) {
		@ids = grep {$_->[1] =~ /L/} @ids;
		# wall also contains the sequential wall number
		$wall = ($wall % 10) || 1;
		return $ids[$wall - 1]->[0] if @ids >= $wall;
		$self->error("Not enough pillars for wall %1 at %2", $wall,
			$self->num2pos($x, $y));
		return undef;
	} else {
		@ids = grep {$_->[1] !~ /L/} @ids;
		# generate entries for tiles with connections at more than one z:
		# lift, helix, tiptube, mixer, dispenser
		my @id2 = grep {$_->[1] =~ /x[FHMTV]/} @ids;
		my @t;
		for my $tile (@id2) {
			push @t, $_ for @$tile;
			if ($t[1] eq 'xM' or $t[1] eq 'xV') {
				$t[4] = $t[4] + 7;
			} elsif ($t[1] eq 'xT') {
				$t[4] = $t[4] + 2;
			} elsif ($t[1] eq 'xH') {
				$t[4] = $t[4] + $t[5];
			} elsif ($t[1] eq 'xF') {
				my $n = $1 if $t[5] =~ /(\d)/;
				$t[4] = $t[4] + 4*$n - 1;
			}
			push @ids, [@t];
		}
		if (@ids > 1) {
			# resolve ambiguity by sorting according to z difference
			@ids = sort {abs($a->[4] - $z) <=> abs($b->[4] - $z)} @ids;
		}
		# vertical tunnel needs 2 ids at the same position, 1st has dz=0
		shift @ids if $r eq 't';
		my %dz0 = (t=>7, a=>5, b=>14, c=>5, d=>5, xT=>2, xM=>7, xV=>7, xt=>7);
		my %dz1 = (s =>5, m=>7, l=>8, t=>7, a=>7, b=>18, c=>7, d=>7, g=>7,
			q=>7, xT=>2, xM=>7, xV=>7, xt=>7);
		return undef if ! @ids;
		my $zdiff = abs($z - $ids[0]->[4]);
		my $zmin = exists $dz0{$r} ? $dz0{$r} : 0;
		my $zmax = exists $dz1{$r} ? $dz1{$r} : 10;
		warn loc("Warning: height difference %1 from z=%4 at %5 for rail %2 at %3 maybe too small\n",
			$zdiff/2., $r, $self->num2pos($x, $y), $z/2., $self->num2pos($xf, $yf)) if $zdiff < $zmin;
		warn loc("Warning: height difference %1 from z=%4 at %5 for rail %2 at %3 maybe too large\n",
			$zdiff/2., $r, $self->num2pos($x, $y), $z/2.,
			$self->num2pos($xf, $yf)) if $zdiff > $zmax;
		return $ids[0]->[0] if @ids;
	}
	return undef;
}

sub no_rail_connection {
	my ($self, $elem) = @_;
	return 1 if ! $elem;
	return $elem =~ /\d+|^[+\^BEOR]/;
}

sub rail_xy {
	my ($self, $r, $x1, $y1, $dir, $detail) = @_;
	return if ! defined $dir or $dir !~ /^[0-6]$/;
	# length of rails
	my %len = (
		a=>2, b=>4, c=>1, d=>1, e=>1, l=>4, m=>3, g=>5, q=>5, s=>2,
		t=>0, u=>4, v=>4, xa=>4, xb=>5, xl=>4, xm=>3, xs=>2, xt=>1,
	);
	my $len = $len{$r} || 0;
	# special case for variable bridge length, default 4 elements
	$len = $detail/2 + 1 if $r eq 'xb';
	my ($x2, $y2) = $self->to_position($x1, $y1, $dir, $len);
	# flextube and bent rails
	if ($r eq 'xt' or $r eq 'c' or $r eq 'd') {
		$dir = $r eq 'xt' ? $detail : $r eq 'c' ? $dir - 1 : $dir + 1;
		($x2, $y2) = $self->to_position($x2, $y2, $dir, 1);
	}
	$self->error("Position (%1,%2) is outside of board", $x2, $y2)
		if $x2 <= 0 or $y2 <= 0;
	return ($x2, $y2);
}

sub verify_rail_endpoints {
	# possible connections on tiles
	my $cases = {
		A => [0, 2, 4], C => [0, 1, 2, 4], D => [0], F => [0], G => [0],
		H => [0, 3], I => [0, 3], J => [0, 3], K => [3], M => [0, 3],
		N => [0, 1, 3, 5], P => [0, 2, 4], Q => [0, 3], S => [0, 2, 4],
		T => [0, 4], U => [0, 2, 4], V => [0, 3], W => [0, 2, 3, 4],
		X => [0, 1, 3, 4], Y => [0, 2, 4], Z => [0, 2, 4], xA => [0, 3],
		xB => [0, 3], xC => [qw(0 1 2 3 4 5)], xD => [1, 5], xF => [0],
		xH => [0, 5], xI => [qw(0 1 2 3 4 5)], xK => [3],
		xM => [qw(0 1 2 3 4 5)], xQ => [0, 1], xR => [0, 3],
		xS => [qw(0 1 2 3 4 5)],
		xT => [0, 5], xV => [0, 2, 4], xW => [0, 1, 3, 4],
		xX => [qw(0 1 2 3 4 5)], xY => [qw(0 1 2 3 4)], xZ => [0, 3],
		yC => [qw(0 1 3 4)], yH => [qw(0 1 2 3 4 5)], yI => [qw(0 1 3 5)],
		yT => [qw(0 1 2 3 4 5)], yV => [qw(0 1 2 3 4 5)], yW => [qw(0 2 3 5)],
		yX => [qw(0 1 2 3 4 5)], yY => [qw(0 2 3 4 5)],
	};
	my ($self, $data) = @_;
	# remember the tile positions
	my %t_pos;
	my ($level, $z0) = (0, 0);
	for (@$data) {
		if ($_->[0] eq 'line') {
			$self->{line}= $_->[1];
			next;
		}
		($level, $z0) = ($_->[1], $_->[2]) if $_->[0] eq 'level';
		next if  length $_->[0] > 2;
		my $z = $_->[3];
		# exclude elements that cannot be start/end points for rails
		next if $self->no_rail_connection($_->[0]) or $_->[0] =~ /L/;
		my $pos = $self->num2pos($_->[1], $_->[2]);
		$self->error("At %1 level %2 is already a tile %3",
			$pos, $level, $t_pos{$pos}{$z}->[0]) if exists $t_pos{$pos}{$z};
		$t_pos{$pos}{$z} = [$_->[0], $_->[5]];
	}
	# check if connections exist with that orientation of tiles and rail
	for my $t (@$data) {
		if ($t->[0] eq 'line') {
			$self->{line}= $t->[1];
			next;
		}
		for my $r (@$t) {
			# skip header data and marbles
			next if ! ref $r or $r->[0] eq 'o';
			# exclude elements that cannot be start points for rails
			next if $self->no_rail_connection($t->[0]);
			# exclude walls, connection is possible to every side of a pillar
			next if $r->[2] =~ /x[sml]/;
			my $from = $self->num2pos($t->[1], $t->[2]);
			if ($t->[0] eq 'xH') {
				# variable direction for spiral depending on number of elements
				$cases->{xH}[1] = (2*$t->[4] - 1) % 6;
			} elsif ($t->[0] eq 'xF') {
				# Lift: upper direction of connection is stored in detail
				$cases->{xF}[1] = ord($1) - 97 if $t->[4] =~ /([a-f])/;
			}
			my $to = $self->num2pos($r->[0], $r->[1]);
			# special case finish line
			if ($r->[2] eq 'e') {
				$self->error("Already a tile at end point of %1",
					$self->{elem_name}{$r->[2]}) if exists $t_pos{$to};
			} elsif (exists $t_pos{$to}) {
				# from tile
				my ($tile, $dir, $to_dir, $ok);
				for my $k (keys %{$t_pos{$from}}) {
					$ok = 0;
					($tile, $dir) = @{$t_pos{$from}{$k}};
					$cases->{xF}[1] = ($cases->{xF}[1] - $dir) % 6
						if $tile eq 'xF';
					# skip height tiles
					next if ! $tile;
					my $my_dir = $r->[3];
					$my_dir = $r->[4] if defined $r->[4] and $r->[2] ne 'xb';
					$ok = 1 if defined $dir
						and grep {$my_dir == ($_+$dir)%6} @{$cases->{$tile}};
					# special case vertical tube (not all situations covered)
					last if $r->[2] eq 't' and keys %{$t_pos{$from}} == 2 and ! $ok;
					last if $ok;

				}
				my $chr = defined $dir ? chr(97 + $dir) : '?';
				my $to_chr = defined $r->[3] ? chr(97 + $r->[3]) : '?';
				$self->error("No connection from tile %1 at %2 orientation %3 to rail %4%5", $tile, $from, $chr, $r->[2], $to_chr) if ! $ok;
				# to tile
				$ok = 0;
				for my $k (keys %{$t_pos{$to}}) {
					($tile, $dir) = @{$t_pos{$to}{$k}};
					# skip height tiles, missing dir was already reported
					next if ! $tile;
					# variable direction for spiral in and Lift out
					if ($tile eq 'xH') {
						my ($h) = grep {$_->[0] eq 'xH' and $r->[0] == $_->[1]
							and $r->[1] == $_->[2]} @$data;
						$cases->{xH}[1] = (2*$h->[4] - 1) % 6;
					} elsif ($tile eq 'xF') {
						my ($f) = grep {$_->[0] eq 'xF' and $r->[0] == $_->[1]
							and $r->[1] == $_->[2]} @$data;
						$cases->{xF}[1] = ord($1) - 97 if $f->[4] =~ /([a-f])/;
						$cases->{xF}[1] = ($cases->{xF}[1] - $dir) % 6;
					}
					my $reverse = 3;
					# vertical rail: no reverse, curved rail: adjust
					if ($r->[2] eq 't') {
						$reverse = 0;
					} elsif ($r->[2] eq 'c') {
						$reverse = 2;
					} elsif ($r->[2] eq 'd') {
						$reverse = 4;
					} elsif ($r->[2] eq 'xt') {
						$reverse = 3 + $r->[4] - $r->[3];
					}
					$to_dir = ($r->[3] + $reverse) % 6;
					$ok = 1 if defined $dir
						and grep {$to_dir == ($_+$dir)%6} @{$cases->{$tile}};
				}
				$chr = defined $dir ? chr(97 + $dir) : '?';
				$to_chr = defined $to_dir ? chr(97 + $to_dir) : '?';
				$self->error("No connection from rail %4%5 to tile %1 at %2 orientation %3", $tile, $to, $chr, $r->[2], $to_chr) if ! $ok;

			# rail end point missing
			} else {
				my $rail = loc($self->{elem_name}{$r->[2]});
				my $from = $self->num2pos($t->[1],$t->[2]);
				$self->error("No tile at %1 %2 -> %3", $rail, $from, $to);
			}
		}
	}
}

sub store_person {
	my ($self, $person, $star, $comment) = @_;
	my $dbh = $self->{dbh};
	$comment = $comment ? "'$comment'" : 'NULL';
	my $sql = "INSERT OR IGNORE INTO person (name,comment)
		VALUES('$person', $comment)";
	$dbh->do($sql);
	$sql = "SELECT id FROM person WHERE name='$person'";
	my $id = ($dbh->selectrow_arrayref($sql))[0][0];
	$sql = "UPDATE config SET main_user=$id";
	$sql .= " WHERE main_user IS NULL" if ! $star;
	$dbh->do($sql);
	return $id;
}

sub store_material {
	my ($self, $data) = @_;
	my ($item, $item_id, $material, $sthi, $sthu, $sthuc, $sthd);
	my $err = $self->{warn};
	# do not store material if errors exist
	$self->error("%quant(%1,Error) found in input!", $err) if $err;
	return 0 if $err;
	my $dbh = $self->{dbh};
	my $comment;
	if ($data->[0][0] eq 'comment') {
		my $header = (shift @$data)[0];
		$comment = $header->[1];
	}
	my ($owner, $star) = ('self', '');
	# check if owner given
	if ($data->[0][0] eq 'owner') {
		my $header = (shift @$data)[0];
		$owner = $header->[1];
		$star = $header->[2];
		$comment .= $header->[3] if $header->[3];
	}
		my $id = @{$dbh->selectall_arrayref('SELECT person_id
			FROM person_elem')}[0];
		$star = 1 if ! $id;
	my $person_id = $self->store_person($owner, $star, $comment);
	if ($self->{db} =~ /memory/) {
		say loc("Checking material for %1", $owner);
	} else {
		say loc("Registering material for %1", $owner);
	}
	my $sql = 'INSERT INTO person_elem (person_id,element,count,comment)
		VALUES (?,?,?,?)';
	my $sth_i_pe = $dbh->prepare($sql);
	$sql = 'INSERT INTO person_set (person_id,set_id,count,comment)
		VALUES (?,?,?,?)';
	my $sth_i_ps = $dbh->prepare($sql);
	$sql = 'UPDATE person_elem SET person_id = ?, count = ? WHERE element=?';
	my $sth_u_pe = $dbh->prepare($sql);
	$sql = 'UPDATE person_set SET person_id = ?, count = ? WHERE set_id=?';
	my $sth_u_ps = $dbh->prepare($sql);
	$sql = 'UPDATE person_elem SET person_id = ?, comment = ? WHERE element=?';
	my $sth_u_pec = $dbh->prepare($sql);
	$sql = 'UPDATE person_set SET person_id = ? ,comment = ? WHERE set_id=?';
	my $sth_u_psc = $dbh->prepare($sql);
	$sql = "DELETE from person_elem WHERE person_id=? AND element=?";
	my $sth_d_pe = $dbh->prepare($sql);
	$sql = "DELETE from person_set WHERE person_id=? AND set_id=?";
	my $sth_d_ps = $dbh->prepare($sql);
	my $sets = $self->query_table(
		'set_id,count', 'person_set', "person_id=$person_id");
	my $elems = $self->query_table(
		'element,count', 'person_elem', "person_id=$person_id");
	for my $d (@$data) {
		my ($count, $item_id, $comment) = @$d;
		if ($item_id =~ /^\d+$/) {
			# register elements
			$item = $self->{elem_name}{$item_id};
			$material = $elems;
			$sthi = $sth_i_pe;
			$sthu = $sth_u_pe;
			$sthuc = $sth_u_pec;
			$sthd = $sth_d_pe;
		} else {
			# register sets
			($item, $item_id) = ($item_id, $self->{set_id}{$item_id});
			$material = $sets;
			$sthi = $sth_i_ps;
			$sthu = $sth_u_ps;
			$sthuc = $sth_u_psc;
			$sthd = $sth_i_ps;
		}
		if (exists $material->{$item_id}) {
			my $oldcnt = $material->{$item_id};
			if ($oldcnt) {
				my $Y = lc loc('Y');
				my $yn = $self->prompt(loc("You have %1 x '%2', add/store %3?",
					$oldcnt, $item, $count));
				# always accept the english answer y
				$count += $oldcnt if $yn =~/[y$Y]/i;
			}
			if ($count) {
				$sthu->execute($person_id, $count, $item_id);
				$sthuc->execute($person_id, $comment, $item_id) if $comment;
			} else {
				$sthd->execute($person_id, $item_id);
			}
		} else {
			$sthi->execute($person_id, $item_id, $count, $comment) if $count;
		}
		$material->{$item_id} = $count;
		say loc("stored %1 x '%2' for id %3", $count, $item, $person_id)
			if $self->{verbose};
	}
}

sub store_run_header {
	my ($self, $data) = @_;
	my $dbh = $self->{dbh};
	my $flds = join(',', keys %$data);
	my $vals = join(',', map {$dbh->quote($_)} values %$data);
	my $sql = "INSERT OR IGNORE INTO run ($flds) VALUES($vals)";
	$dbh->do("INSERT OR IGNORE INTO run ($flds) VALUES($vals)");
	$sql = "SELECT id FROM run WHERE digest='$data->{digest}'";
	my $id = ($dbh->selectrow_arrayref($sql))[0][0];
	$dbh->do("DELETE FROM run_tile WHERE run_id=$id");
	$dbh->do("DELETE FROM run_rail WHERE run_id=$id");
	$dbh->do("DELETE FROM run_marble WHERE run_id=$id");
	$dbh->do("DELETE FROM run_comment WHERE run_id=$id");
	return $id;
}

sub store_run {
	my ($self, $data) = @_;
	# more checks before trying to store run
	$self->verify_rail_endpoints($data);
	$self->{line} = 0;
	# do not store run if errors exist
	if ($self->{warn}) {
		$self->error("%quant(%1,Error) found in input!", $self->{warn});
		$self->{warn}--; #do not count line above as additional error
		return 0 if ! exists $self->{db} or $self->{db} ne ':memory:';
	}
	my ($hdr, $comment, $run_id, $level, $marbles, $seen, $rail);
	# prepare insert, select and update statement handles
	my $dbh = $self->{dbh};
	my $sql = 'INSERT INTO run_tile
		(run_id,element,posx,posy,posz,detail,orient,level)
		VALUES(?,?,?,?,?,?,?,?)';
	my $sth_i_rt = $dbh->prepare($sql);
	$sql = 'UPDATE run SET marbles=? WHERE id=?';
	my $sth_u_r = $dbh->prepare($sql);
	$sql = 'INSERT INTO run_marble (run_id,tile_id,orient,color)
		VALUES(?,?,?,?)';
	my $sth_i_rm = $dbh->prepare($sql);
	$sql = 'INSERT INTO run_rail (run_id,tile1_id,tile2_id,
		element,direction,detail) VALUES(?,?,?,?,?,?)';
	my $sth_i_rr = $dbh->prepare($sql);
	$sql = "SELECT id FROM run_rail
		WHERE tile1_id IN (?) AND tile2_id=? AND run_id=?";
	my $sth_sel_rr = $dbh->prepare($sql);
	for my $d (@$data) {
		if ($d->[0] eq 'line') {
			$self->{line}= $d->[1];
			next;
		}
		# collect header data
		if ($d->[0] =~ /^name|^date|^author|^source/) {
			$hdr->{$d->[0]} = $d->[1];
			$level = 0;
			$marbles = 0;
			$run_id = undef;
			$seen = undef;
			next;
		} elsif ($d->[0] =~ /^comment/) {
			$comment = $d->[1];
			next;
		}
		# store header data
		if ($hdr) {
			my $str;
			$str .= $hdr->{$_} for sort keys %$hdr;
			# check if we want to update only
			my $digest = md5_base64($str);
			$hdr->{digest} = $digest;
			my $run_name = $self->translate($hdr->{name});
			if (exists $hdr->{author}) {
				$hdr->{person_id} = $self->store_person($hdr->{author});
				delete $hdr->{author};
			}
			if (exists $self->{run_ids}{$digest}) {
				my $yn = $self->prompt(
					loc("Marble run '%1' existing, replace it?", $run_name));
				my $Y = loc('Y');
				return undef if $yn !~ /^[y$Y]/i;
			}
			if ($self->{db} =~ /memory/) {
				say loc("Checking marble run '%1'", $run_name);
			} else {
				say loc("Registering marble run '%1'", $run_name);
			}
			$run_id = $self->store_run_header($hdr);
			$hdr = undef;
		}
		if ($d->[0] eq 'level') {
			$level = $d->[1];
			next;
		}
		# store tile data: tile_char, x, y, z, detail, orient level
		#                          0  1  2  3       4       5     6
		my @val = @{$d}[0..6];
		$sth_i_rt->execute($run_id, @val) if $val[0];
		next if $self->no_rail_connection($val[0]) and ! $comment;
		my $id = @{$dbh->selectall_arrayref('SELECT last_insert_rowid()
			FROM run_tile')}[0]->[0];
		$dbh->do("INSERT OR IGNORE INTO run_comment (run_id,tile_id,comment)
			VALUES('$run_id', '$id', '$comment')") if $comment and $run_id;
		$comment = undef;
		next if $self->no_rail_connection($val[0]);
		# exclude height tiles and transparent plane from being rail end points
		push @$seen, [$id, @val];
		for my $aref (@$d) {
			next if ! ref $aref;
			# store marble data

			if (exists $aref->[0] and $aref->[0] eq 'o') {
				$marbles++;
				$sth_u_r->execute($marbles, $run_id);
				$sth_i_rm->execute($run_id, $id, @{$aref}[1..$#$aref]);
			} else {
				# rail data: id, x1, y1, z, detail,orient,level, x2, y2, r, dir
				my $to_tile = "$aref->[0],$aref->[1]";
				$val[0] = $id;
				push @$rail, ['line', $self->{line}], [@val, @$aref];
			}
		}
	}
	# store rail data
	for my $r (@$rail) {
		if ($r->[0] eq 'line') {
			$self->{line}= $r->[1];
			next;
		}
		#r: from_id x1 y1 z1 detail orient from_level, x2, y2, rail_id, dir wall
		#         0  1  2  3      4      5          6   7   8        9   10   11
		# chose correct tile: tile normally placed at same or lower level
		my $id = $self->find_to_tile($r, $seen);
		# finish lines have no end tile
		if ($id or $r->[9] eq 'e') {
			$sth_sel_rr->execute($id, $r->[0], $run_id);
			if ($sth_sel_rr->fetchrow_array) {
				$self->error("Rail %1 already registered from %2 to %3",
					$r->[9], $self->num2pos($r->[7], $r->[8]),
					$self->num2pos($r->[1], $r->[2]));
			} else {
				$sth_i_rr->execute($run_id, $r->[0], $id, @{$r}[9 .. 11]);
			}
		} else {
			$self->error("No end point for rail %1 from %2 to %3",
				$r->[9],
				$self->num2pos($r->[1], $r->[2]),
				$self->num2pos($r->[7], $r->[8]));
		}
	}
	if (! $run_id) {
			$self->error("No valid data found");
			return undef;
	}
	# now calculate board size and maximum level
	$sql = "SELECT max(posx),max(posy),max(level) FROM run_tile
		WHERE run_id=$run_id";
	my @vals = @{($dbh->selectall_array($sql))[0]};
	$dbh->do("UPDATE run SET size_x = $vals[0] ,size_y = $vals[1],
		layers = $vals[2] WHERE id=$run_id");
	$self->{run_ids} = $self->query_table('digest,id', 'run');
	return $run_id;
}

sub get_pos {
	my ($self, $pos, $relative) = @_;
	my ($x1, $y1) = (0, 0);
	if ($relative and $pos =~ /^([0-5])([0-6])$/) {
		($x1, $y1) = ($1, $2);
	} elsif (! $relative and $pos =~ /^([\da-z])([\da-z])$/i) {
		($x1, $y1) = ($1, $2);
		$x1 = ord(lc $x1) - 87 if $x1 =~ /[a-z]/i;
		$y1 = ord(lc $y1) - 87 if $y1 =~ /[a-z]/i;
	} else {
		$self->error("Wrong tile position '%1'", $pos);
	}
	return ($x1, $y1);
}

sub plane_lines {
	my ($self, $lines) = @_;
	my $loc_level = loc('Level');
	my ($level, $max_level, $line) = (0, 0, 0);
	for (grep {/^\d+\s+[\^#]*(?:level|$loc_level)/i} @$lines) {
		$max_level = $1 if /(?:level|$loc_level)\s*(\d+)/i and $1 > $max_level;
	}
	my ($level_pos, $added);
	for (@$lines) {
		$line++;
		$added = 0, next if $added;
		if (/^\d+\s+[=^#]*_/) {
			$level = 0;
			$level_pos = 0;
		# analyse level line
		} elsif (/^\d+\s+[=^#]*(?:level|$loc_level)(?:[:=\s]+|$)(.*)/i) {
			$level = $1;
			if ($level !~ /^\d+$/) {
				my $bad = $level || '';
				$level = ++$max_level;
				s/$bad$/ $level/;
				$self->error("Wrong level number '%1' becomes level %2",
					$bad, $level) if $bad;
			}
			$level_pos = $level ? $line : 0;
		# transparent plane line
		} elsif (/^(\d+)\s+[^#]*[=^]/) {
			if (! $level_pos) {
				# add level line
				$level = ++$max_level;
				splice @$lines, $line - 1, 0, "$1 Level $level";
				$added = 1;
				$level_pos = $line - 1;
			} elsif ($level_pos < $line - 1) {
				# move transparent plane definition up after the level line
				splice @$lines, $level_pos, 0, splice(@$lines, $line - 1, 1);
			}
			$level_pos = 0;
		}
	}
}

sub get_offsets {
	my ($self, $lines) = @_;
	$self->plane_lines($lines);
	my $loc_level = loc('Level');
	my $off = [[0, 0, 0]];
	my $relative = $self->{relative} = 0;
	my ($level_seen, $col, $row);
	my $line = 0;
	my $level = 0;
	my @adjust;
	for (@$lines) {
		$line++;
		/^line (\d+)$/;
		$self->{line}= $1;
		# process only plane related lines (level, _, ^ and = lines)
		next if $_ !~ /^[\w\s]+[=^_]|^level|^$loc_level/i;
		if (/^\d+\s+_\s*(\d+)\D+(\d+)/) {
			$relative = $self->{relative} = 1;
			$level = 0;
			next if ! $2;
			$col = 5*($1 - 1);
			$row = 6*($2 - 1);
			$level_seen = 0;
			$off->[0] = [$row, $col, 0];
		} elsif (/^\d+\s+(?:level|$loc_level)(?:\s+|:|$)(.*)/i) {
			$level = $1;
			if ($level =~ /^\d+/) {
				$level_seen = 1;
			} else {
				my $bad = $level || '';
				$level = 1;
				$level++ while defined $off->[$level];
				s/$bad$/ $level/;
				$self->error("Wrong level number '%1' becomes level %2",
					$bad, $level) if $bad;
			}
		} elsif (/^\d+\s+([0-9a-z]{2})\s+.*([=^])/i) {
			my $type = ($2 eq '=') ? 2 : 3;
			($row, $col) = $self->get_pos($1, $relative);
			if (! $level_seen) {
				$level++ while defined $off->[$level];
				# add level lines later, if missing
				push @adjust, [$line - 1, "Level $level"]
			}
			$level_seen = 0;
			if ($relative) {
				$col += $off->[0][0];
				$row += $off->[0][1];
			}
			if (defined $off->[$level]) {
				my $pos = $self->num2pos($off->[$level][0], $off->[$level][1]);
				$self->error("Level %1 already seen at %2", $level, $pos)
					if $col != $off->[$level][0] or $row != $off->[$level][1];
			} else {
				$off->[$level][0] = $col;
				$off->[$level][1] = $row;
				$off->[$level][2] = $type;
			}
		}
	}
	splice @$lines, $_->[0], 0, $_->[1] for @adjust;
	return $off;
}

sub marble_orients {
	my ($self, $marbles, $rule) = @_;
	# silently add/correct orientations if possible
	my ($tile, $dir) = @{$rule}[0,5];
	my $off = $dir % 2;
	$off = 1 - $off if $tile eq 'N';
	my %orient = ($off => 1, $off+2 => 1, $off+4 =>1);
	for my $r (grep {$_->[0] eq 'o'} map {$rule->[$_]} (7 .. $#$rule)) {
		# silently add/correct orientations
		if ($tile =~ /^M|x[AFTZ]/) {
			$r->[1] = $dir;
			next;
		} elsif ($tile =~ /^[ANP]/) {
			if (defined $r->[1] and exists $orient{$r->[1]}) {
				delete $orient{$r->[1]};
			} elsif (defined $r->[1]) {
				$self->error("marble on tile %1, dir %2 cannot be in position %3",
				$tile, chr($dir + 97), chr($r->[1] + 97));
			}
		} else {
			$self->error("No marbles should be placed on the %1 tile", $tile);
		}
	}
	return if $tile !~ /^[ANP]/;
	for my $r (grep {$_->[0] eq 'o'} map {$rule->[$_]} (7 .. $#$rule)) {
		if (! defined $r->[1]) {
			my $val = (keys %orient)[0];
			delete $orient{$val};
			$r->[1] = $val;
		}
	}
}

sub level_height {
	my ($self, $rules, $off_xy, $h) = @_;
	my $old_z = 0;
	for (my $l=0; $l < @$off_xy; $l++) {
		next if ! defined $off_xy->[$l];
		my ($x0, $y0) = @{$off_xy->[$l]};
		next if ! $x0;
		my $delta = ($off_xy->[$l][2] || 3) - 1;
		my $z = 0;
		my $height = 0;
		if ($l) {
			for (keys %$h) {
				my ($level, $x, $y) = split /,/;
				next if $l <= $level;
				next if abs($x - $x0) > $delta or abs($y - $y0) > $delta;
				next if abs($x - $x0) + abs($y - $y0) > $delta + 1;
				$height = $h->{$_} if $h->{$_} > $height;
			}
			$z = $height + 1;
		# if plane is at same position as previous, add its height
		$z += $old_z if $x0 == $off_xy->[$l-1][0] and $y0 == $off_xy->[$l-1][1];
		}
		for (grep {$_->[0] eq 'level' and $_->[1] == $l} @$rules) {
			push @$_, $z;
		}
		for (grep {defined $_->[6] and $_->[6] == $l} @$rules) {
			$_->[3] += $z;
		}
		$old_z = $z;
	}
}

sub balcony_height {
	my ($self, $rules, $wall) = @_;
	my (%b_z, %wall_num);
	my $l_max = 0;
	for (grep {$_->[0] =~ /x?L/} @$rules) {
		push @{$b_z{"$_->[1],$_->[2]"}}, $_->[3];
		$l_max = $_->[6] if $_->[6] > $l_max;
	}
	# lower walls come first after sorting
	my $pos_z;
	for (sort keys %$wall) {
		my ($x, $y, $dir, $pillar) = split /,/;
		$pillar-- if $pillar;
		my ($r, $wall_num) = @{$wall->{$_}};
		for my $i (1 .. 3) {
			last if $r eq 'xm' and $i > 2 or $r eq 'xs' and $i > 1;
			my ($x2, $y2) = $self->to_position($x, $y, $dir, $i);
			$pos_z->{"$x2,$y2"} = [$pillar, $wall_num, $b_z{"$x,$y"}]
				if ! exists $pos_z->{"$x2,$y2"};
		}
	}
	my $oldpos = "0,0";
	my $inc = 0;
	for (@$rules) {
		$self->{line} = $_->[1] if $_->[0] eq 'line';
		next if length $_->[0] > 2;
		my ($elem, $x, $y, $z, $detail, $dir) = @{$_}[0..5];
		my $pos = "$x,$y";
		next if $pos ne $oldpos and $elem ne 'B';
		# adjust z of tiles on top of balcony
		if ($elem ne 'B') {
			$_->[3] += $inc if $inc;
			$_->[6] = $l_max;
			next;
		}
		# treat balconies, set a default for the detail, if not given
		my $hole = $detail % 14;
		my $num_pillar = int($detail/14);
		$oldpos = $pos;
		my ($x2, $y2) = $self->to_position($x, $y, $dir, 1);
		($x2, $y2) = $self->to_position($x, $y, ($dir + 1) % 6, 1)
			if ! exists $pos_z->{"$x2,$y2"};
		# calculate z for balconies and store the hole number as a detail
		if (exists $pos_z->{"$x2,$y2"}) {
			my ($pillar, $wall_num, $z) = @{$pos_z->{"$x2,$y2"}};
			# get pillar number from balcony if walls stacked
			$pillar = $num_pillar - 1 if $num_pillar;
			if ($pillar < @$z) {
				$inc = $z->[$pillar] - 14;
				$_->[3] = 2*$hole + $inc;
				$_->[6] = $l_max;
				# store in addition wallnumber in detail
				$_->[4] += 100*$wall_num;
			} else {
				$self->error("Pillar %1 does not exist, number too large",
					$pillar + 1);
			}
		} else {
			for my $d ($dir + 2 .. $dir + 5) {
				($x2, $y2) = $self->to_position($x, $y, $d % 6, 1);
				next if ! exists $pos_z->{"$x2,$y2"};
				$_->[5] = $d % 6;
				$self->error("Change balcony direction %1 to %2 at %3 hole %4",
					chr($dir + 97), chr($_->[5] + 97), $self->num2pos($x, $y),
					$hole);
				last;
			}
			$self->error("No wall for balcony at %1 in hole %2",
				$self->num2pos($x, $y), $hole) if $_->[5] == $dir;
		}
	}
}

sub doublebalcony_height {
	my ($self, $rules) = @_;
	my %e_z;
	my $l_max = 0;
	for (grep {$_->[0] eq 'E' or $_->[0] eq 'line'} @$rules) {
		$self->{line} = $_->[1] if $_->[0] eq 'line';
		next if $_->[0] ne 'E';
		push @{$e_z{"$_->[1],$_->[2]"}}, [$self->{line}, $_->[3], $_->[5]]
			if $_->[3];
		$l_max = $_->[6] if $_->[6] > $l_max;
	}
	for (grep {($_->[0] eq 'E' or $_->[0] eq 'line') and ! $_->[3]} @$rules) {
		$self->{line} = $_->[1] if $_->[0] eq 'line';
		next if $_->[0] ne 'E' or $_->[3];
		$_->[6] = $l_max;
		my ($x2, $y2, $detail, $dir) = ($_->[1], $_->[2], $_->[4], $_->[5]);
		my ($x, $y) = $self->to_position($x2, $y2, 3 + $dir, 1);
		$detail ||= 1;
		$self->{line} = $e_z{"$x,$y"}->[0][0] if exists $e_z{"$x,$y"};
		if (exists $e_z{"$x,$y"} and grep {$_->[2] != $dir} @{$e_z{"$x,$y"}}) {
			(my $dirstr = $dir) =~ tr/0-5/a-f/;
			$self->error("Wrong direction %1 for double balcony at %2", $dirstr,
				$self->num2pos($x, $y));
		} elsif (exists $e_z{"$x,$y"} and defined $e_z{"$x,$y"}->[$detail - 1]) {
			$_->[3] = $e_z{"$x,$y"}->[$detail - 1][1];
		} else {
			$self->error("Double balcony %1 at %2 described but not seen at %3",
				$detail, $self->num2pos($x2, $y2), $self->num2pos($x, $y));
		}
		my $past_E = 0;
		my $detail2 = 1;
		for (grep {length $_->[0] < 3 and $_->[1] == $x2 and $_->[2] == $y2}
			@$rules) {
			$detail2 ||= $_->[4] if $_->[0] eq 'E';
			next if $_->[0] ne 'E' and ! $past_E;
			next if $detail != $detail2;
			$past_E = 1;
			next if $self->no_rail_connection($_->[0]);
			$_->[3] += $e_z{"$x,$y"}->[$detail - 1][1] || 0;
			$_->[6] = $l_max;
			$past_E = 0;
		}
	}
}

sub parse_run {
	my ($self, $content) = @_;
	my ($rules, $comment, $run_name, $off_x, $off_y, $off_xy, $plane_type, $level_line_seen, $wall);
	my ($h);
	my $level = 0;
	my $loc_name = loc('Name');
	my $loc_author = loc('Author');
	my $loc_source = loc('Source');
	my $loc_date = loc('Date');
	my $loc_level = loc('Level');
	my $loc_pos = loc('Position');
	# in the presence of _ lines location data are relative to the base plate
	my $rel_pos = 0;
	# split content into lines with line numbers prepended
	my $i = 0;
	my @lines = map {$i++;map {"$i $_"} split /;/, $_} split /\r?\n/, $content;
	# determine offsets for transparent planes and its plane numbers
	$off_xy = $self->get_offsets(\@lines);
	my $num_wall = 0;
	for (@lines) {
		# strip off and remember line numbers, skip empty lines
		s/^(\d+)\s+//;
		$self->{line} = $1;
		push @$rules, ['line', $1];
		# first line is the name of the run if no name line given
		$run_name = $_ if ! $run_name and ($1 || 0) == 1;
		next if /^\s*$/;
		s/\s*$//;
		# strip off and remember comments
		if (s/(\s*#.*)//) {
			# a comment without further info
			if (! $_) {
				$comment .= "$1\n";
				next;
			# if we had already a comment, we create a rule
			} elsif ($comment) {
				push @$rules, ['comment', $comment];
			}
			# an inline comment;
			$comment .= $1;
			push @$rules, ['comment', $comment];
			$comment = undef;
		# no further comment lines, store a rule
		} elsif ($comment) {
			push @$rules, ['comment', $comment];
			$comment = undef;
		}
		# analyse header lines
		if (/^\s*(?:name|$loc_name)(?:\s+|:|$)(.*)/i) {
			$run_name = $1;
			$self->error("Missing run name") if ! $run_name;
		} elsif (s/^\s*(?:level|$loc_level)(?:\s+|:)(\d+)//i) {
			# errors already reported
			$level_line_seen = 1;
			$level = $1;
			pop @$rules if $rules->[-1][0] eq 'level';
			push @$rules, ['level', $level];
		} elsif (/^\s*(?:date|$loc_date)(?:\s+|:)(.*)/i) {
			push @$rules, ['date', $1];
			$self->error("Missing run name") if /^$run_name$/;
		} elsif (/^\s*(?:author|$loc_author)(?:\s+|:)(.*)/i) {
			push @$rules, ['author', $1];
			$self->error("Missing run name") if /^$run_name$/;
		} elsif (/^\s*(?:source|$loc_source)(?:\s+|:)(.*)/i) {
			push @$rules, ['source', $1];
			$self->error("Missing run name") if /^$run_name$/;
		} elsif ($self->{line} == 1) {
			# already covered
			$self->{line} = 2;
		# ground planes
		} elsif (s/^\s*_\s*//) {
			if (/(\d+)\D+(\d+)/) {
				($off_y, $off_x) = ($1, $2);
				$off_xy->[0] = [6*($off_x - 1), 5*($off_y - 1)];
				$rel_pos = 1;
				push @$rules, ['level', 0] if $level;
				$level = 0;
			} else {
				$self->error("Incorrect ground plane numbering '%1' '%2'",
					$off_x, $off_y);
			}
		# tile positions, rails and marbles
		} else {
			my ($x1, $y1, $z, $tile_id, $tile_name, $r, $dir, $detail, $f);
			my ($pos, $tile, @items) = split;
			($y1, $x1) = $self->get_pos($pos, $rel_pos);
			$off_x = $off_xy->[$level][0] || 0;
			$off_y = $off_xy->[$level][1] || 0;
			$plane_type = $off_xy->[$level][2] || 3;
			# adjust positions exept for transparent plane
			if ($tile and $rel_pos) {
				if ($tile =~ /[=^]/) {
					$x1 += $off_xy->[0][0];
					$y1 += $off_xy->[0][1];
				} else {
					# adjust y coordinate if transparent plane on even x pos
					$y1++ if ! ($off_xy->[$level][0] % 2 + $x1 % 2) and $level;
					$x1 += $off_x;
					$y1 += $off_y;
					$x1 -= $plane_type if $level;
					$y1 -= $plane_type if $level;
				}
			}
			# tile must be on a transparent plane for level > 0
			my $delta = $plane_type - 1;
			$self->error("Wrong tile position '%1'", $pos) if $level
				and $tile !~ /[=^]/
				and (abs($x1 - $off_x) > $delta or abs($y1 - $off_y) > $delta
				or abs($x1 - $off_x) + abs($y1 - $off_y) > $delta + 1);
			# no further analysis if position missing, error reported in get_pos
			next if ! defined $y1;
			# height, tile, orientation
			if (defined $tile) {
				# height elements 1..9,a..d,+,B,E,L,xL
				$z = 0;
				my $skip_be = 0;
				while ($tile =~ s/^([+\dBEabcd]|x?L)//) {
					my $elem = $1;
					my ($dir, $detail);
					my $inc = 0;
					# treat balconies, determine z after the content is parsed
					if ($elem eq 'E') {
						$detail = $1 if $tile =~ s/^(\d)//;
						if ($z) {
							$inc = 1;
						} else {
							$z = 0;
							$detail ||= 1;
							$skip_be = 1;
						}
					} elsif ($tile =~ s/^B(\d?)// or $elem eq 'B') {
						$detail = $1 || 0;
						$skip_be = 1;
						if ($elem =~ /([1-9])|([a-d])/) {
							my $hole = $1 || ord($2) - 87;
							$detail = 14*$detail + $hole;
							$z = 2*$hole;
						} elsif ($elem eq 'B') {
							$detail = 0;
							$z = 0;
						} else {
							$self->error("Wrong balcony height '%1'", $elem);
						}
						$elem = 'B';
					}
					# direction for balconies
					if ($elem =~ /^[BE]|xL/) {
						if ($tile =~ s/^([a-f])//) {
							$dir = $1;
							$dir =~ tr/a-f/0-5/;
						} else {
							$self->error("Direction missing for balcony %1",
								$elem);
							$dir = 0;
						}
					}
					if ($elem =~ /^(\d)/) {
						$inc += 2*$1;
					} elsif ($elem eq '+') {
						$inc++;
					} elsif ($elem =~ /x?L/) {
						$inc += 14;
					}
					$z += $inc;
					# remember the heights for height of transparent plane
					my $corr = 1;
					if ($tile !~ /[=^]/) {
						$h->{"$level,$x1,$y1"} = $z if ! $skip_be;
						$corr = 0;
					}
						push @$rules,
						[$elem, $x1, $y1, $z, $detail, $dir, $level - $corr] if $elem;
				}
				# tile special cases S,U,xH,xB,xF,O,xM,xD
				if ($tile) {
					# handle Switch position + / -
					if ($tile =~ s/([SU])([+-]?)/$1/) {
						$detail = $2 || '';
					} elsif ($tile =~ s/xD([+-]?)/xD/) {
						$detail = $1 || '';
					# handle number of helix elements
					} elsif ($tile =~ s/xH(\d*)/xH/) {
						$detail = $1 || 2;
						$self->error("Helix must have at least 2 elements")
							if $detail < 2;
					# handle number of bridge unfolding elements
					} elsif ($tile =~ s/xB(\d?)(\D)/xB$2/) {
						$detail = $1 || 4;
						$self->error("Even number of elements expected, not %1",
							$detail) if $detail % 2;
						push @items, "xb$2";
					# lift (number of elements and orientation out)
					} elsif ($tile =~ s/xF(.*)([a-f])/xF$2/) {
						$detail = $1;
						($dir = $2) =~ tr /a-f/d-fa-c/;
						$detail =~ /([2-9]?)([a-f]?)/ if $detail;
						# default 4 elements and opposite direction
						$detail = ($1 || 4) . ($detail ? $2 : $dir);
					# Trampolin with angle tiles
					} elsif ($tile =~ s/R([a-fA-F]+)/R/) {
						$detail = lc $1;
						$detail =~ tr/a-f/0-5/;
					# Mixer
					} elsif ($tile =~ s/xM([a-fA-F])([a-fA-F])/xM$2/) {
						$detail = lc $1;
						$dir = lc $2;
						$detail =~ tr/a-f/0-5/;
						$dir =~ tr/a-f/0-5/;
						$self->error("For the mixer orientation %1 the direction %2 of the outgoing ball is not possible", $1, $2) if  ($dir + $detail) % 2;
					# open basket
					} elsif ($tile =~ /^O/) {
						$self->error("Tile 'O' needs no height data") if $z;
					}
					# tile symbol and direction
					$_ = $tile;
					$tile = $1 if s/^([xyz]?[=^A-Za-w])//;
					if (s/^([a-f])//i) {
						$dir = $1;
						$dir =~ tr/a-fA-F/0-50-5/;
						$self->error("%quant(%1,Excessive char) '%2'",
							length $_, $_) if $_;
					} else {
						$self->error("Wrong orientation char '%1'", $_) if $_;
					}
				}
				next if ! $tile and ! @items;
				# check for tile errors (height tiles have tile = '')
				if (exists $self->{elem_name}{$tile}) {
					$tile_name = loc($self->{elem_name}{$tile});
					$self->error("%1 '%2' is not a tile", $tile_name, $tile)
						if $tile =~ /[a-w]/;
					$self->error("Missing tile orientation for '%1'", $tile)
						if ! defined $dir and $tile !~ /[OR^=]/;
					$self->error("Tile '%1' needs no orientation", $tile)
						if defined $dir and $tile =~ /[OR^=]/;
				} elsif ($tile) {
					$self->error("Wrong tile char '%1'", $tile);
				} else {
					$self->error("In %1 no tile data found","@items")
						if grep {$_ !~ /x[lms]/} @items;
				}
			} else {
				$self->error("Position without further data");
			}
			$f = [$tile, $x1, $y1, $z, $detail, $dir, $level];
			next if ! defined $tile;
			if (! @items or ! grep {/o/} @items) {
				my @m1 = qw(oRa oGc oBe);
				my @m2 = qw(oRb oGd oBf);
				(my $dirchr = $dir || 0) =~ tr/0-5/a-f/;
				push @items, @m1 if $tile =~ /^[AP]$/ and ! ($dir % 2);
				push @items, @m2 if $tile =~ /^[AP]$/ and $dir % 2;
				push @items, @m1 if $tile eq 'N' and ($dir % 2);
				push @items, @m2 if $tile eq 'N' and ! $dir % 2;
				push @items, "oS$dirchr", "oS$dirchr" if $tile eq 'M';
				push @items, "oS$dirchr" if $tile =~ /x[AZ]/;
				if ($tile eq 'xF') {
					push @items, 'oS' for 1..(3 + 4*(substr($detail,0,1) - 2));
				}
			}
			if (@items and $tile =~ /[O^=]/) {
				$self->error("Unexpected data for %1: %2", $tile_name,"@items");
				next;
			}
			# rails and marbles
			my ($marbles, $rails);
			for (@items) {
				# marbles
				my $count = 1;
				$count = $1 if s/^(\d+)o/o/;
				if (s/^o(.*)/$1/) {
					my ($orient, $color);
					if ($_) {
						if (s/([a-f])//) {
							$orient = ord($1) - 97;
						}
						if (s/([RGBS])//) {
							$color = $1;
						} elsif ($tile =~ /^[ANP]/) {
							$color = substr('RGB', ($marbles||0) % 3, 1);
						}
						$self->error("%quant(%1,Excessive char) '%2'",
							length $_, $_) if $_;
					}
					# no marbles for count = 0 !
					$marbles += $count;

					push @$f, ['o', $orient, $color] for 1 .. $count;
					$self->error("%1 marbles seen, 3 is maximum", $marbles)
						if $marbles > 3 and $tile ne 'xF';
				} elsif (s/^(x?[A-Za-w])//) {
				# all known rails (exists and range of small letters)
					$r = $1;
					my ($is_wall, $w_detail);
					my $pillar = 0;
					# treat walls, define sequential wall number
					if ($r =~ /x[sml]/) {
						$is_wall = ++$num_wall;
						$pillar = $1 if s/^(\d)//;
						$w_detail = 10*$num_wall + $pillar;
					}
					if ($r !~ /^(x?[a-egl-nqs-v])/
							or ! exists $self->{elem_name}{$r}) {
						$self->error("Wrong rail char '%1'", $1);
					} elsif (s/^([a-f])//i) {
						$dir = $1;
						if ($r eq 'xt') {
							if (! s/^([a-f])//i) {
								$self->error("Flextube needs two directions");
							} else {
								$detail = $1;
								($dir, $detail) = ($detail, $dir);
								$w_detail = $detail;
								$w_detail =~ tr/a-fA-F/0-50-5/;
							}
						}
						$w_detail = $detail if $r eq 'xb';
						$dir =~ tr/a-fA-F/0-50-5/;
						push @{$wall->{"$x1,$y1,$dir,$pillar"}}, $r,$num_wall
							if $is_wall;
						my ($x2, $y2) =
							$self->rail_xy($r, $x1, $y1, $dir, $w_detail);
						if (exists $rails->{$dir}) {
							$self->error("Rail direction %1 already seen", $dir)
								if ! $is_wall;
						}
						if ($tile) {
							push @$f, [$x2, $y2, $r, $dir, $w_detail];
						} else {
							push @{$rules->[-1]}, [$x2, $y2, $r, $dir, $w_detail];
						}
						$rails->{$dir} = 1 if ! $detail;
					} elsif (s/(.)//) {
						$self->error("Wrong rail direction '%1'", $1);
					} elsif (! $_) {
						$self->error("Missing rail direction for '%1'", $r);
					}
					if ($_) {
						$self->error("%quant(%1,Excessive char) '%2'",
							length($_), $_);
					}
				} else {
					$self->error("Wrong rail data '%1'", $_);
				}
			}
			my $n = scalar (keys %$rails);
			$self->error("%1 rail data seen, 3 is maximum", $n) if $n > 3;
			push @$rules, $f;
			$self->marble_orients($marbles, $rules->[-1]) if $marbles;
		}
	}
	unshift @$rules, ['name', $run_name];
	# add the height of transparent planes to the level line and the tiles
	$self->level_height($rules, $off_xy, $h);
	# find wall for the balconies, check orientation and adjust height and level
	$self->balcony_height($rules, $wall);
	# add z to the double balcony lines and adjust level
	$self->doublebalcony_height($rules);
	undef $self->{line};
	return $rules;
}

sub parse_material {
	my ($self, $contents) = @_;
	my @lines = split(/[\n;]/, $contents);
	my $rules;
	# check input for formal correctness only
	my $comment;
	for (@lines) {
		$self->{line}++;
		next if /^\s*$/;
		# treat comments
		if (s/\s*#(.*)//) {
			# a comment without further info
			if (! $_) {
				$comment .= "$1\n";
				next;
			# if we had already a comment, we create a rule
			} elsif ($comment) {
				push @$rules, ['comment', $comment];
			}
			# an inline comment;
			$comment = $1;
		# no further comment lines, store a rule
		} elsif ($comment) {
			push @$rules, ['comment', $comment];
			$comment = undef;
		}
		# check for owner in first nonempty or non comment line
		if ((! $rules or @$rules == 1 and $rules->[0][0] eq 'comment')
			and $_ !~ /\d/) {
			my $locowner = loc('Owner');
			s/\s*(owner|$locowner):?\s+//i;
			# if a star is found in the line, it is the principal owner
			my $star = ($_ =~ s/\s*\*\s*//);
			push @$rules, ['owner', $_, $star, $comment];
		# material
		} elsif (/(-?\d+)\s*x?\s+(.*)/) {
			my ($count, $item) = ($1, $2);
			$item =~ s/\s$//g;
			if ($item =~ /^x?.$/) {
				if (! exists $self->{elem_name}{$item}) {
					$self->error("Unknown element %1",$item);
					$item = '';
				}
				push @$rules, [$count, $item, $comment];
				next;
			}
			my %set_names = map {loc($_), $_} keys %{$self->{set_id}};
			my %set_reverse = reverse %set_names;
			# try exact names, if no match, try substrings
			my @list = grep {lc $_ eq lc $item} values %set_names;
			my @list2 = grep {lc $_ eq lc $item} keys %set_names;
			if (@list + @list2 == 0) {
				@list = grep {/^$item/i} values %set_names if @list;
				@list2 = grep {/^$item/i} keys %set_names;
			}
			# we have a known set
			if (@list == 1 and @list2 == 0 or (
				@list == 1 and @list2 == 1
				and $list[0] eq $set_names{$list2[0]})) {
				push @$rules, [$count, $list[0], $comment];
			} elsif (@list == 0 and @list2 == 1) {
				push @$rules, [$count, $set_names{$list2[0]}, $comment];
			# report ambig names (localized version first)
			} elsif (@list2 > 1) {
				$self->error("Ambig set name '%1': %2", $item, "@list2");
			} elsif (@list > 1) {
				$self->error("Ambig set name '%1': %2", $item, "@list");
			} else {
				$self->error("Unknown set name '%1': ", $item);
			}
		} else {
			$self->error("Unknown material line '%1'", $_);
		}
		$comment = undef;
	}
	undef $self->{line};
	return $rules;
}
1;
__END__
=encoding utf-8
=head1 NAME

Game::MarbleRun::Store - Store marble runs

=head1 SYNOPSIS

  #!/usr/bin/perl
  use Game::MarbleRun::Store;
  $g = Game::MarbleRun::Store->new();
  $g->process_input($_) for @ARGV;
  $g->finish();

=head1 DESCRIPTION

Game::MarbleRun::Store provides the process_input method to read a file
containing instructions for building a marble track or giving the number
of owned GraviTrax® construction sets and elements.
file.

=head1 METHODS

=head2 new (constructor)

$g = Game::MarbleRun::Store->new(%attr);

Creates a new game object and initializes a sqlite database if not yet
existing. By default the DB is located at ~/.gravi.db in the callers home
directory. The DB is populated initially with information on GraviTrax®
construction sets and elements. The following attrs can be used:

  verbose => 1               sets verbosity
  db      => "<file name>"   alternate name and place of the DB

=head2 process_input

$g->process_input(file_name);

Reads lines of input from a file given by its name, parses and checks the
contents for correctness and transforms it into an internal representation.
Finally the data get stored in the DB. The file format is described in
Game::MarbleRun.

=head1 HELPER METHODS

=head2 find_to_tile

$tile_id = $g->find_to_tile($rail, $seen);

returns the tile_id for the end point of a rail from the database table
run_tile. The seen variable is an arrayref populated with information from
all seen tiles and rail is an arrayref that contains the rail description
(from and to positions, rail symbol etc.). Returns undef on error.

=head2 no_rail_connection

$ok = $g->no_rail_connection($elem);

Returns 1 if the element cannot be a starting point of a rail.

=head2 rail_xy

($x2, $y2) = $g->rail_xy($rail, $x1, $y1, $dir, $num);

calculate the rail endpoint for a rail identified by its rail character, start
point x1, y1 and direction dir. For unfolding rails the number num of elements
used can be given, otherwise 4 is assumed.

=head2 verify_rail_endpoints

$g->verify_rail_endpoints($data);

verifies that the rails end on a tile. The data arrayref is the intermediate
format after parsing and before storage in the DB. Called from store_run.

=head2 store_person

$id = $g->store_person($person_name, $main_user_flagi, $comment);

stores a person name in the DB and returns the person id. If the main_user_flag
is set, that person becomes the main user (default for displaying material,
calculating if material for a run suffices etc.) Additional information about a
user can be placed in the comment variable and gets stored in the DB.

=head2 store_material

$g->store_material($data);

stores the parsed material data in the DB.

=head2 store_run_header

$run_id = $g->store_run_header($data);

stores the parsed run header data in the DB and returns the run id

=head2 store_run

$run_id = $g->store_run($data);

stores the parsed run data in the DB and returns the run id

=head2 get_pos

($x, $y) = $g->get_pos($pos, $relative);

calculates the integer row and column positions from the two character
input string and checks its correctness. Both absolute notation 1..9a..z
and relative positions are handled. Returns (0, 0) on error, which is
a position outside of the board.

=head2 get_offsets

$offsets = $g->get_offsets($lines);

calculates the transparent plane coordinate offsets during parsing the
input. Outputs an arrayref containing
$offsets->[$level] = [column_off, row_off, type] for a given level. The
plane type is 0, 2 or 3 for ground/small/large transparent plane. Adds
level lines before the transparent plane line (^) if not already present.

=head marble_orients

$g->marble_orients($marbles, $rule);

checks position of marbles and adds silently marbles if missing (e.g. two
marbles for cannons).

=head2 level_height

$g->level_height($rules, $off_xy, $h);

Calculates the heights of transparent planes by finding the maximum
height of the tiles below the transparent plane and adds it to the tiles
on these planes, i.e. the rule contents gets modified. The tiles are
described by the hashrefs $h and $off_xy.

=head2 balcony_height

$g->balcony_height($rules, $wall);

Updates the heights of balconies by checking the vertical position of the
wall they are connected to. All heights for elements on top of the balconies
are updated as well. As for level_height the rule contents gets updated.
The walls are described by the hashref $wall.

=head2 doublebalcony_height

$g->doublebalcony_height($rules);

Updates the heights for elements on top of the double balconies. Checks
if the two lines needed for the double balcony consistently describe the
element. As for level_height the rule contents gets updated.

=head2 parse_run

$data = $g->parse_run($contents);

parses the input, checks it for formal correctness and returns the
parsed data.

=head2 parse_material

$data = $g->parse_material($contents);

parses the input, checks it for formal correctness and returns the
parsed data.

=head1 SEE ALSO

See also the documentation in Game::MarbleRun and Game::MarbleRun::Draw.
The file gravi_en.pdf and gravi_de.pdf (in german) describe in more detail
the notation of marble runs.

=head1 AUTHOR

Wolfgang Friebel, E<lt>wp.friebel@gmail.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2020, 2021 by Wolfgang Friebel

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.28.1 or,
at your option, any later version of Perl 5 you may have available.

=cut

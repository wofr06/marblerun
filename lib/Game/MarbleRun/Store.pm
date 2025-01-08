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

my $dbg = 0;

sub new {
	my ($class, %attr) = @_;
	my $self = {};
	bless $self => $class;
	$self->config(%attr);
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
		local $/ = undef;
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

sub no_rail_connection {
	my ($self, $elem) = @_;
	return 1 if ! $elem or $elem =~ /\d+|^[+\^=BEOR]|^z\+/;
}

sub rail_xy {
	my ($self, $r, $x1, $y1, $dir, $detail, $level) = @_;
	return if ! defined $dir or $dir !~ /^[0-5]$/;
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
		if $x2 < 0 or $y2 < 0;
	return ($x2, $y2);
}

sub verify_rail_endpoints {
	my ($self, $data) = @_;
	# remember the tile positions
	my ($t_pos);
	my $level = 0;
	for my $i (0 .. $#$data) {
		my $t = $data->[$i];
		if ($t->[1] eq 'line') {
			$self->{line}= $t->[2];
		} elsif ($t->[1] eq 'level') {
			$level = $t->[2];
		}
		next if ! $t->[0];
		next if $self->no_rail_connection($t->[1]);
		my $z = $t->[4] || 0;
		my $pos = $self->num2pos($t->[2], $t->[3]);
		$self->error("At %1 level %2 (%3) is already a tile %4", $pos, $level,
			$z, $data->[$t_pos->{$pos}{$z}][1]) if exists $t_pos->{$pos}{$z};
		$z -= 14 if $t->[1] =~ /^x?L/;
		$t_pos->{$pos}{$z} = $i;
	}
	# check if connections exist with that orientation of tiles and rail
	for my $t (@$data) {
		if ($t->[1] eq 'line') {
			$self->{line}= $t->[2];
		}
		# exclude header data
		next if ! $t->[0];
		# exclude elements that cannot be start points for rails
		next if $self->no_rail_connection($t->[1]);
		my $z = $t->[4] || 0;
		for my $r (@$t[8..$#$t]) {
			# skip marble data
			next if $r->[0] eq 'o';
			my $from = $self->num2pos($t->[2], $t->[3]);
			my $to = $self->num2pos($r->[0], $r->[1]);
			# special case finish line
			if ($r->[2] eq 'e') {
				$self->error("Already a tile at end point of %1",
					$self->{elem_name}{$r->[2]}) if exists $t_pos->{$to};
				next;
			}
			# from tile
			my $z_from = $self->rail_connection($t, $r);
			$_ += $t->[4] for @$z_from;
			# to tiles
			my $z_to;
			my $reverse = 3;
			# vertical rail: no reverse, curved rail, flextube: adjust
			if ($r->[2] eq 't') {
				$reverse = 0;
			} elsif ($r->[2] eq 'c') {
				$reverse = 2;
			} elsif ($r->[2] eq 'd') {
				$reverse = 4;
			} elsif ($r->[2] eq 'xt') {
				$reverse = 3 + $r->[4] - $r->[3];
			}
			for my $z (keys %{$t_pos->{$to}}) {
				my $i = $t_pos->{$to}{$z};
				# special case for walls
				if ($r->[2] =~ /x[sml]/) {
					my $ind = $data->[$i];
					if ($ind->[1] =~ /^x?L/ and abs($z + 14 - $ind->[4]) <= 1) {
						$r->[5] =$ind->[0];
						$z_to = [[$i, $ind->[4] + 14]];
					}
					next;
				}
				my $zs = $self->rail_connection($data->[$i], $r, $reverse);
				push @$z_to, [$i, $_ + $data->[$i][4]] for @$zs;
				$r->[5] = $data->[$i][0] if $z_to;
			}
			if ($dbg) {
				say "$t->[1] $from -> rail $r->[2]", chr(97 + $r->[3]),
					" to $to (z=@$z_from)";
				for my $z_inc (@$z_from) {
					say " from z=", $z_inc, " to ", $data->[$_->[0]][1],
						" z=", $_->[1] for @$z_to;
				}
			}
			my $chr = defined $t->[6] ? chr(97 + $t->[6]) : '?';
			if (! $z_from or ! @{$z_from}) {
				my $to_chr = defined $r->[3] ? chr(97 + $r->[3]) : '?';
				$self->error("No connection between tile %1 at %2 orientation %3 and rail %4%5", $t->[1], $from, $chr, $r->[2], $to_chr);
			}
			if (! $z_to or ! @{$z_to}) {
				my $rail_dir = ($r->[3] + $reverse) % 6;
				my $to_chr = defined $rail_dir ? chr(97 + $rail_dir) : '?';
				$self->error("No connection to a tile from %1 at %2 orientation %3 and rail %4%5", $t->[1], $from, $chr, $r->[2], $to_chr);
			}
			# resolve z ambiguities
			$self->resolve_z($r, $z_from, $z_to, $from, $data);
		}
	}
}

sub resolve_z {
	my ($self, $r, $from, $to, $t_pos, $data) = @_;
	return if ! $from or ! $to or ! @$from or ! @$to;
	$r->[5] = $data->[$to->[0][0]][0] if @$to == 1;
	return if @$from == 1 and @$to == 1;
	$from = [sort {$a <=> $b} @$from];
	$to = [sort {$a->[1] <=> $b->[1]} @$to];
	# resolve ambiguity by sorting according to z difference
	my %dz0 = (t=>6, a=>5, b=>14, c=>5, d=>5, xT=>2, xM=>7, yH=>7, yS=>7,
		yT=>7, xt=>6);
	my %dz1 = (s =>5, m=>7, l=>8, t=>8, a=>7, b=>18, c=>7, d=>7, g=>7,
		q=>7, xT=>2, xM=>7, yH=>7, yS=>7, yT=>7, xt=>8);
	my $zlow = exists $dz0{$r->[2]} ? $dz0{$r->[2]} : 0;
	my $zhigh = exists $dz1{$r->[2]} ? $dz1{$r->[2]} : 10;
	my $id_min = $to->[0][0];
	my $id_strict;
	exit if ! defined $to->[0][1];
	my $zmin = abs($to->[0][1] - $from->[0]);
	my $zstrict = 999;
	for my $zf (@$from) {
		for my $t (@$to) {
			my $zdiff = abs($zf - $t->[1]);
			if ($zdiff < $zmin) {
				$zmin = $zdiff;
				$id_min = $t->[0];
			}
			if ($zdiff < $zstrict and $zdiff >= $zlow and $zdiff <=$zhigh) {
				$zstrict = $zdiff;
				$id_strict = $t->[0];
			}
		}
	}
	undef $zstrict if $zstrict == 999;
	my $zdiff = $zstrict || $zmin;
	my $id = $id_strict || $id_min;
	$r->[5] = $data->[$id][0];
	my ($xf, $yf, $z) = @{$data->[$id]}[2,3,4];
	say " z=$z taken" if $dbg;
	warn loc("Warning: height difference %1 from z=%4 at %5 for rail %2 at %3 maybe too small\n",
		$zdiff/2., $r->[2], $t_pos, $z/2., $self->num2pos($xf, $yf)) if $zdiff < $zlow;
	warn loc("Warning: height difference %1 from z=%4 at %5 for rail %2 at %3 maybe too large\n",
		$zdiff/2., $r->[2], $t_pos, $z/2.,
		$self->num2pos($xf, $yf)) if $zdiff > $zhigh;
}

sub rail_connection {
	my ($self, $t, $r, $reverse) = @_;
	my $tile = $t->[1];
	return [[0]] if $tile =~ /\|/;
	my $z_from;
	$reverse ||= 0;
	my $rail_dir = ($r->[3] + $reverse) % 6;
	my $tile_dir = $t->[6];
	# ignore checks for pillars and new/unknown tiles
	if ($tile =~ /^x?L|\|/) {
		$z_from = [0] if $r->[2] =~ /x[sml]/ or $tile =~ /\|/;
	} else {
		my $case2;
		if ($tile eq 'xH') {
			# direction in for spiral depends on number of elements
			my $in = $t->[5] % 6 if $t->[5] =~ /^\d+$/;
			$case2 = [[(2*$in - 1)%6, $in]] if defined $in;
		} elsif ($tile eq 'xF') {
			# direction out for lift at z!=0 is stored in detail
			my $out = ord($2) - 97 if $t->[5] =~ /(\d)([a-f])/;
			$case2 = [[($out - $t->[6]) % 6, 7*($1 - 1)]] if $out;
		} elsif ($tile ne 'J' and exists $self->{conn1}{$tile}) {
			for my $k (keys %{$self->{conn1}{$tile}}) {
				push @$case2, [$_, $k]
					for @{$self->{conn1}{$tile}{$k}};
			}
		}
		if (defined $tile_dir
			and grep {$rail_dir == ($_+$tile_dir)%6} @{$self->{conn0}{$tile}}) {
			$z_from = [0];
		}
		for my $case (@$case2) {
			if (defined $tile_dir and $rail_dir==($case->[0] + $tile_dir) % 6) {
				push @$z_from, $case->[1];
			}
		}
	}
	return $z_from;
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
		(id,run_id,element,posx,posy,posz,detail,orient,level)
		VALUES(?,?,?,?,?,?,?,?,?)';
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
	$sql = 'INSERT INTO run_no_elements (run_id,board_x,board_y) VALUES(?,?,?)';
	my $sth_i_no = $dbh->prepare($sql);
	my $run_seen = 0;
	for my $d (@$data) {
		if ($d->[1] eq 'line') {
			$self->{line}= $d->[2];
			next;
		}
		# collect header data
		if ($d->[1] =~ /^name|^date|^author|^source/) {
			($hdr->{$d->[1]} = $d->[2]) =~ s/^\s*// if defined $d->[2];
			$level = 0;
			$marbles = 0;
			$run_id = undef;
			$seen = undef;
			next;
		} elsif ($d->[1] =~ /^comment/) {
			$comment = $d->[2];
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
			$self-> update_meta_data($run_seen) if $run_seen;
			$run_id = $self->store_run_header($hdr);
			$hdr = undef;
			$run_seen = $run_id;
		}
		if ($d->[1] eq 'level') {
			$level = $d->[2];
			next;
		}
		if ($d->[1] eq 'exclude') {
			$sth_i_no->execute($run_id, $d->[2], $d->[3]);
			next;
		}
		# store tile data: id char, x, y, z, detail, orient level rails,marbles
		#                   0    1  2  3  4       5       6     7 8...
		if ($d->[1] eq 'O') {
			# register direction of outgoing marble in basket
			my @r_o = map {$_->[3]} grep {$_->[0] eq 'o'} @{$d}[8 .. $#$d];
			$d->[6] = $r_o[0] if defined $r_o[0];
		}
		my @val = @{$d}[0..7];
		$val[4] ||= 0; # check for unassigned z value
		say "store $val[0], $run_id", map {defined $_ ? " $_" : ' ?'} @val[1 .. 7] if $dbg;
		$sth_i_rt->execute($val[0], $run_id, @val[1 .. 7]) if $val[1];
		next if $self->no_rail_connection($val[1]) and ! $comment;
		my $id = $val[0];
		$dbh->do("INSERT OR IGNORE INTO run_comment (run_id,tile_id,comment)
			VALUES('$run_id', '$id', '$comment')") if $comment and $run_id;
		$comment = undef;
		next if $self->no_rail_connection($val[1]);
		# exclude height tiles and transparent plane from being rail end points
		push @$seen, [@val];
		for my $aref (@$d[8 .. $#$d]) {
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
		#r: from_id chr x1 y1 z1 detail orient level, x2, y2, rail_id, dir wall
		#         0   1  2  3  4      5      6     7   8   9       10   11   12
		# t: tile_id tile_char, x, y, z, detail, orient level
		#          0         1  2  3  4       5       6     7
		# chose correct tile: tile normally placed at same or lower level
		my $id = $r->[13];
		undef $id if defined $id and $id == $r->[0];
		# finish lines have no end tile
		if ($id or $r->[10] eq 'e') {
			$sth_sel_rr->execute($id, $r->[0], $run_id);
			if ($sth_sel_rr->fetchrow_array) {
				$self->error("%1 already registered from %2 to %3",
					loc($self->{elem_name}{$r->[10]}), $self->num2pos($r->[8],
					$r->[9]), $self->num2pos($r->[2], $r->[3]));
			} else {
				say "store $r->[0], $id, @{$r}[10, 11]" if $dbg;
				$sth_i_rr->execute($run_id, $r->[0], $id, @{$r}[10, 11, 12]);
			}
		# error already reported
		#} else {
		#	$self->error("No end point for %1 from %2 to %3",
		#		$r->[10],
		#		#loc($self->{elem_name}{$r->[10]}),
		#		$self->num2pos($r->[2], $r->[3]),
		#		$self->num2pos($r->[8], $r->[9]));
		}
	}
	if (! $run_id) {
			$self->error("No valid data found");
			return undef;
	}
	$self-> update_meta_data($run_id);
	return $run_id;
}

sub update_meta_data {
	my ($self, $run_id) = @_;
	my $dbh = $self->{dbh};
	# now calculate board size and maximum level
	my $sql = "SELECT max(posx),max(posy),max(level) FROM run_tile
		WHERE run_id=$run_id";
	my @vals = @{($dbh->selectall_array($sql))[0]};
	@vals = (0, 0, 0) if ! defined $vals[0];
	$dbh->do("UPDATE run SET size_x = $vals[0] ,size_y = $vals[1],
		layers = $vals[2] WHERE id=$run_id");
	$self->{run_ids} = $self->query_table('digest,id', 'run');
}

sub get_pos {
	my ($self, $pos, $relative) = @_;
	my ($x1, $y1) = (0, 0);
	if ($relative and $pos =~ /^([0-5])([0-6])$/) {
		($x1, $y1) = ($1, $2);
	} elsif (! $relative and $pos =~ /^([\da-z])([\da-z])$/i) {
		($x1, $y1) = ($1, $2);
		$x1 = ($x1 =~ /[a-z]/i) ? ord(lc $x1) - 87 : int $x1;
		$y1 = ($y1 =~ /[a-z]/i) ? ord(lc $y1) - 87 : int $y1;
	} elsif (! $relative and $pos =~ /^(\d+),(\d+)$/i) {
		($x1, $y1) = (int $1, int $2);
	} else {
		$self->error("Wrong tile position '%1'", $pos);
	}
	return ($x1, $y1);
}

sub plane_lines {
	my ($self, $lines) = @_;
	my $loc_level = loc('Level');
	my $off = [[0, 0, 0]];
	my $relative = $self->{relative} = 0;
	my ($level, $max_level, $line) = (0, 0, 0);

	for (@$lines) {
		my ($what, $value) = $self->header_line($_);
		next if ! $what or $what ne 'level';
		$max_level = $value if  $value > $max_level;
	}
	my ($level_pos, $added, $col, $row, $type);
	for my $str (@$lines) {
		($_ = $str) =~ s/^(\d+)\s+//;
		my $orig_line = $1;
		$line++;
		my ($what, $value) = $self->header_line($_);
		next if $what and $what ne 'level';
		$added = 0, next if $added;
		if (/^_\s*(\d+)\D+(\d+)/) {
			$relative = $self->{relative} = 1;
			next if ! $2;
			$col = 5*($1 - 1);
			$row = 6*($2 - 1);
			$off->[0] = [$row, $col, 0];
			$level = 0;
			$level_pos = 0;
		# analyse level line
		} elsif ($what and $what eq 'level') {
			$level = $value;
			# bad level error reported in parse_run
			$level = ++$max_level if $level !~ /^\d+$/;
			$level_pos = $level ? $line : 0;
		# transparent plane line
		} elsif (/^[^#]*[=^]/) {
			if (/([0-9a-z]{2}|\d+,\d+)\s+.*([=^])/i) {
				$type = ($2 eq '=') ? 2 : 3;
				($row, $col) = $self->get_pos($1, $relative);
			}
			if (! $level_pos and $type > 0) {
				# add level line
				$level = ++$max_level;
				splice @$lines, $line - 1, 0, "$orig_line Level $level";
				$added = 1;
				$level_pos = $line - 1;
			} elsif ($type > 0 and $level_pos < $line - 1) {
				# move transparent plane definition up after the level line
				splice @$lines, $level_pos, 0, splice(@$lines, $line - 1, 1);
			}
			$level_pos = 0;
			if ($relative) {
				$col += $off->[0][0];
				$row += $off->[0][1];
			}
			# duplicate level line error reported in parse_run
			if (!defined $off->[$level]) {
				$off->[$level][0] = $col;
				$off->[$level][1] = $row;
				$off->[$level][2] = $type;
			}
		}
	}
	return $off;
}

sub level_height {
	my ($self, $rules, $off_xy, $h) = @_;
	my @ldone =(0);
	for my $lev (sort keys %$off_xy) {
		my ($x0, $y0) = @{$off_xy->{$lev}};
		if (! defined $x0) {
			$self->error("Position unknown for level %1", $lev);
			return;
		}
		my $delta = ($off_xy->{$lev}[2]);
		my $z = 0;
		my %height;
		my $height = 0;
		if ($lev) {
			for (@$h) {
				my ($x, $y, $z, $l) = @$_;
				next if ! grep {$l == $_} @ldone;
				next if abs($x - $x0) > $delta - 1 or abs($y - $y0) > $delta - 1;
				next if abs($x - $x0) + abs($y - $y0) > $delta;
				$height = $z if $z > $height;
				$height{$z}++;
			}
			$z = $height + 1;
			my $h_elems = exists $height{$height} ? $height{$height} : 0;
			warn loc("Only %1 height elements for plane %2 seen\n", $h_elems, $lev) if $h_elems < 3;
			# update info in $h
			for (@$h) {
				$_->[2] += $z if $_->[3] == $lev;
			}
			push @ldone, $lev if $h_elems >= 3;
		}
		push @$_, $z for grep {$_->[1] eq 'level' and $_->[2] == $lev} @$rules;
		$_->[4] += $z for grep {defined $_->[7] and $_->[7] == $lev} @$rules;
	}
}

sub header_line {
	my ($self, $line) = @_;
	my $loc_name = loc('Name');
	my $loc_author = loc('Author');
	my $loc_source = loc('Source');
	my $loc_date = loc('Date');
	my $loc_level = loc('Level');
	return ('name', $1) if /^\s*(?:name|$loc_name)(?:\s+|:|$)(.*)/i;
	return ('date', $1) if /^\s*(?:date|$loc_date)(?:\s+|:|$)(.*)/i;
	return ('author', $1) if /^\s*(?:author|$loc_author)(?:\s+|:|$)(.*)/i;
	return ('source', $1) if /^\s*(?:source|$loc_source)(?:\s+|:|$)(.*)/i;
	return ('level', $1) if /^\s*(?:level|$loc_level)(?:\s+|:|$)(.*)/i;
	return undef;
}

sub parse_run {
	my ($self, $content) = @_;
	my ($rules, $comment, $run_name, $off_xy, $plane_type,
		$level_line_seen, $wall, $pillar, $z_balcony2, $planepos, $planenum);
	# offset for ground planes and center position of transparent planes
	my ($off_x, $off_y) = (0, 0);
	my $level = 0;
	my ($num_L, @pos_L, $num_E, @pos_E, $num_W, $xw, $yw);
	my $num_wall = 0;
	# in the presence of _ lines location data are relative to the base plate
	my $rel_pos = 0;
	# split content into lines with line numbers prepended
	my $i = 0;
	my $old_level = -1;
	my @lines = map {$i++; map {"$i $_"} split /;/, $_} split /\r?\n/, $content;
	$off_xy = $self->plane_lines(\@lines);
	# unique tile number
	my $tid = 1;
	for (@lines) {
		$level = $old_level if $old_level >= 0;
		$old_level = -1;
		# strip off and remember line numbers, skip empty lines
		s/^(\d+)\s+//;
		my $line_no = $1;
		$self->{line} = $line_no;
		push @$rules, [0, 'line', $line_no];
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
				push @$rules, [0, 'comment', $comment];
			}
			# an inline comment;
			$comment .= $1;
			push @$rules, [0, 'comment', $comment];
			$comment = undef;
		# no further comment lines, store a rule
		} elsif ($comment) {
			push @$rules, [0, 'comment', $comment];
			$comment = undef;
		}
		# analyse header lines
		my ($what, $value) = $self->header_line($_);
		# first line is the name of the run if no name line given
		if (! $what and $line_no == 1 and $content =~ /^$_/) {
			$what = 'name';
			$value = $_;
		}
		if ($what and $what eq 'name') {
			$self->error("Redefinition of run name '%1'", $run_name) if defined $run_name;
			$self->error("Missing run name") if ! $value;
		}
		if ($what and $what eq 'name') {
			$run_name = $value;
			if ($self->{db} =~ /memory/) {
				say loc("Checking marble run '%1'", $run_name || '');
			} else {
				say loc("Registering marble run '%1'", $run_name || '');
			}
		} elsif ($what and $what eq 'level') {
			$self->error("Level number not given") if ! defined $value or $value eq '';
			my $good_level = $level;
			$level = $value || 0;
			if ($level) {
				if ($level !~ /^\d+$/) {
					my $bad = $level || '';
					$level = $good_level;
					$level++ while exists $planenum->{$level};
					s/$bad$/ $level/;
					$self->error("Wrong level number '%1' becomes level %2",
						$bad, $level) if $bad;
				}
				$level_line_seen = 1;
				if (exists $planenum->{$level}) {
					my $pos = $self->num2pos($off_xy->[$level][0] || 0,
											 $off_xy->[$level][1] || 0);
					$self->error("Level %1 already seen at %2", $level, $pos);
				}
				$planenum->{$level} = [undef, undef];
			}
			pop @$rules if $rules->[-1][1] eq 'level';
			push @$rules, [0, 'level', $level];
		} elsif ($what) {
			push @$rules, [0, $what, $value];
		# ground planes
		} elsif (s/^_\s*// or /\*/) {
			# small round ground plane
			if (/^(\S+)\s+\*/) {
				($off_x, $off_y) = $self->get_pos($1, $rel_pos);
				$off_xy->[0] = [$off_x, $off_y, -3];
			} elsif (/(\d+)\D+(\d+)/) {
				$off_x = 6*($2 - 1);
				$off_y = 5*($1 - 1);
				$off_xy->[0] = [$off_x, $off_y];
				$rel_pos = 1;
			} else {
				$self->error("Incorrect ground plane numbering '%1'", $_);
			}
			push @$rules, [0, 'level', 0] if $level;
			$level = 0;
		# ground planes not to be drawn
		} elsif (s/^!\s*//) {
			if (/(\d+)\D+(\d+)/) {
				push @$rules, [0, 'exclude', $2, $1];
			} else {
				$self->error("Incorrect ground plane numbering '%1'", $_);
			}
		# tile positions, rails and marbles
		} else {
			my ($x1, $y1, $z, $inc, $tile_id, $tile_name, $r, $dir, $detail, $f);
			my ($pos, $tile, @items) = split;
			($y1, $x1) = $self->get_pos($pos, $rel_pos);
			$off_x = $off_xy->[$level][0] || 0;
			$off_y = $off_xy->[$level][1] || 0;
			$plane_type = $off_xy->[$level][2] || 3;
			if (! defined $tile) {
				$self->error("Position without further data");
				next;
			}
			# adjust positions
			if ($tile and $rel_pos) {
				if ($tile =~ /[=^]|^E|^.B/) {
					$x1 += $off_xy->[0][0];
					$y1 += $off_xy->[0][1];
				} else {
					# adjust y coordinate if transparent plane on even x pos
					$x1 += $off_x;
					$y1 += $off_y;
					if ($level) {
						$x1 -= $plane_type;
						$y1 -= $plane_type;
						$y1++ if !($off_x % 2) and $x1 % 2 and $plane_type == 3;
						$y1-- if $off_x % 2 and !($x1 % 2) and $plane_type == 2;
					}
				}
			}
			# transparent plane position
			if ($tile =~ /^([=^])$/) {
				if (! $level_line_seen) {
					$level++;
					$level++ while exists $planenum->{$level};
				}
				$planenum->{$level} = [$x1, $y1, $plane_type];
				$level_line_seen = 0;
				#push @$rules, [$tid++, $1, $x1, $y1, undef, undef, undef, $level];
			}
			# tile must be on a transparent plane for level > 0
			my $delta = $plane_type - 1;
			$self->error("Wrong tile position '%1'", $pos) if $level
				and $tile !~ /[=^BE]/
				and (abs($x1 - $off_x) > $delta or abs($y1 - $off_y) > $delta
				or abs($x1 - $off_x) + abs($y1 - $off_y) > $delta + 1);
			# no further analysis if position missing, error reported in get_pos
			next if ! defined $y1;
			# height, tile, orientation
			$z = 0;
			my $elem;
			# wall lines
			if ($tile =~ s/^(\d?)(x[lms])([a-f])//) {
				my $detail = $1 || 1;
				$elem = $2;
				$dir = ord($3) - 97;
				$num_wall++;
				my ($x2, $y2) = $self->rail_xy($elem, $x1, $y1, $dir);
				($xw, $yw) = ($x1, $y1);
				$num_L = $pos_L[$detail - 1] || 0;
				$num_W = @{$rules->[$num_L]};
				push @{$rules->[$num_L]}, [$x2, $y2, $elem, $dir, $num_wall, $x1, $y1];
			}
			# double balcony lines (2nd hole)
			if ($tile =~ s/^E//) {
				$elem = 'E';
				if ( ! defined $num_E or ! exists $pos_E[$num_E]) {
					$self->error("First position of double balcony not seen so far");
					$tile = '';
					@items = ();
				} else {
					my $x = $rules->[$pos_E[$num_E]][2];
					my $y = $rules->[$pos_E[$num_E]][3];
					# change level according to position of 1st hole
					$old_level = $level;
					$level = $rules->[$pos_E[$num_E]][7];
					$dir = $self->find_dir($x, $y, $x1, $y1);
					if ($tile =~ s/^([a-f])//) {
						my $dir2 = ord(lc $1) - 97;
						$self->error("Wrong direction %1 for double balcony at %2, should be %3", $1, $self->num2pos($x1, $y1), chr($dir + 97)) if $dir != $dir2;
					}
					$rules->[$pos_E[$num_E]][6] = $dir;
					$z = $rules->[$pos_E[$num_E++]][4];
					push @$rules,
						[$tid++, $elem, $x1, $y1, $z, $num_E, $dir, $level] if $elem;
				}
			# balcony lines
			} elsif ($tile =~ s/^([^xyz]+)B//) {
				$elem = 'B';
				my $hole = $1;
				if ($hole and $hole =~/^(\d)$|^([a-d])$/) {
					$hole = int($1 || ord($2) - 87);
				} else {
					$self->error("Wrong balcony height '%1'", $hole);
					$hole = 0;
				}
				$dir = 0;
				if (! defined $num_L) {
					$self->error("Wall for balcony not yet seen so far");
					$tile = '';
					@items = ();
				} else {
					my $x = $rules->[$num_L][1];
					my $y = $rules->[$num_L][2];
					my $o = $rules->[$num_L][$num_W][3];
					$dir = $self->find_balcony_dir($xw, $yw, $o, $x1, $y1);
					if ($tile =~ s/^([a-f])//) {
						my $dir2 = ord(lc $1) - 97;
						$self->error("Wrong direction %1 for balcony at %2, should be %3", $dir2, $self->num2pos($x1, $y1), $dir) if $dir != $dir2;
						$dir=$dir2;
					}
					my $detail = $num_wall;
					$z = 2*$hole;
					$z += $rules->[$num_L][4] if defined $rules->[$num_L][4];
					push @$rules,
						[$tid++, $elem, $x1, $y1, $z, $detail, $dir, $level] if $elem;
				}
			}
			# other height elements 1..9,+,E,L,xL
			while ($tile =~ s/^([+\dEL]|xL|z[12+])//) {
				$elem = $1;
				# direction for balconies and pillars (for pillar optional)
				if ($elem =~ /^[EL]|xL/) {
					if ($tile =~ s/^([a-f])//) {
						$dir = ord($1) - 97;
					} elsif ($elem eq 'xL') {
						$self->error("Direction missing for element %1",
							$elem);
						$dir = 0;
					}
				}
				if ($elem =~ /^z?(\d)/) {
					$inc = 2*$1;
				} elsif ($elem =~ /^[=^]/) {
					push @$planepos, [$x1, $y1, $z, $level];
					$inc = 1;
				} elsif ($elem =~ /^z?\+/) {
					$inc = 1;
				} elsif ($elem eq 'E') {
					$num_E = 0;
					my ($xE, $yE) = (0, 0);
					($xE, $yE) = @{$rules->[$pos_E[-1]]}[2,3] if @pos_E;
					@pos_E = () if $xE != $x1 or $yE != $y1;
					push @pos_E, scalar @$rules;
					$inc = 1;
				} elsif ($elem =~ /^x?L/) {
					my ($xL, $yL) = (0, 0);
					($xL, $yL) = @{$rules->[$pos_L[-1]]}[2,3] if @pos_L;
					@pos_L = () if $xL != $x1 or $yL != $y1;
					push @pos_L, scalar @$rules;
					$inc = 14;
				}
				# for all height elements
				push @$rules,
					[$tid++, $elem, $x1, $y1, $z, $detail, $dir, $level] if $elem;
				$z += $inc;
			}
			# candidates for transparent plane positions
			push @$planepos, [$x1, $y1, $z, $level] if ! $tile and $elem !~ /[=^]|x[lms]/;
			# tile special cases S,U,xH,xB,xF,O,xM,xD,yR
			# handle Switch position + / -
			if ($tile =~ s/^([SU]|xD)([+-]?)/$1/) {
				$detail = $2 || '';
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
			} elsif ($tile =~ s/^R([a-f]+)/R/) {
				$detail = '';
				$detail .= ord(lc $_) - 97 for split '', $1;
			# Mixer
			} elsif ($tile =~ s/xM([a-f])([a-f])/xM$2/) {
				$detail = ord(lc $1) - 97;
				$dir = ord(lc $2) - 97;
				$self->error("For the mixer with orientation %1 the direction %2 of the outgoing ball is not possible", $1, $2) if ! ($dir + $detail) % 2;
			# Releaser
			} elsif ($tile =~ s/yR([a-f])([a-f])/yR$2/) {
				$detail = ord(lc $1) - 97;
				$dir = ord(lc $2) - 97;
				$self->error("For the releaser with orientation %1 the direction %2 of the outgoing ball is not possible", $1, $2) if ($detail - $dir) % 6 > 3;
			# open basket
			} elsif ($tile =~ /^O/) {
				$self->error("Tile 'O' needs no height data") if $z;
			}
			# tile symbol and direction, allow for |tile_name| notation
			$_ = $tile;
			if (s/^\|(\S+)\|//) {
				$tile = $1;
				my @elem = grep {$self->{elem_name}{$_} eq $tile or loc($self->{elem_name}{$_}) eq $tile} keys %{$self->{elem_name}};
				$tile = $elem[0] ? $elem[0] : "|$tile|";
			} else {
				$tile = $1 if s/^([xyz]?[=^A-Za-z])//;
			}
			if (s/^([a-f])//) {
				$dir = ord($1) - 97;
				$self->error("%quant(%1,Excessive char) '%2'",
					length $_, $_) if $_;
			} else {
				$self->error("Wrong orientation char '%1'", $_) if $_;
			}
			# check for tile errors (height tiles have tile = '')
			if (exists $self->{elem_name}{$tile}) {
				$tile_name = loc($self->{elem_name}{$tile});
				$self->error("%1 '%2' is not a tile", $tile_name, $tile)
					if $tile =~ /[a-df-w]/ and $tile !~ /x[lms]/;
				$self->error("Missing tile orientation for '%1'", $tile)
					if ! defined $dir and $tile !~ /[OR^=]/;
				$self->error("Tile '%1' needs no orientation", $tile)
					if defined $dir and $tile eq 'O';
			} elsif ($tile) {
				$self->error("Wrong tile char '%1'", $tile) if $tile !~ /^\|/;
			} else {
				# not reached
				$self->error("In %1 no tile data found","@items")
					if $tile and grep {$_ !~ /x[lms]/} @items;
			}
			$dir ||= 0; # default for missing direction
			$f = [$tid++, $tile, $x1, $y1, $z, $detail, $dir, $level];
			next if ! defined $tile;
			$self->check_marbles($tile, $dir, $detail, \@items);
			# store marbles
			for (grep {/^\d*o/} @items) {
				my ($count, $color, $dir) = /^(\d*)o(.)(.)/;
				($color, $dir) = ($dir, $color) if $dir !~ /[a-f]/;
				push @$f, ['o', ord($dir) - 97, $color] for 1 .. ($count || 1);
			}
			if (@items and $tile =~ /[=^]/) {
				$self->error("Unexpected data for %1: %2", $tile_name,"@items");
				next;
			}
			# rails
			my $rails;
			for (@items) {
				next if /^\d*o/; # marbles already handled
				if (s/^(x?[A-Za-w])//) {
				# all known rails (exists and range of small letters)
					$r = $1;
					my $w_detail;
					if ($r !~ /^(x?[a-egl-nqs-v])/
							or ! exists $self->{elem_name}{$r}) {
						$self->error("Wrong rail char '%1'", $r);
					} elsif (s/^([a-f])//i) {
						$dir = $1;
						if ($r eq 'xt') {
							if (! s/^([a-f])//i) {
								$self->error("Flextube needs two directions");
								$w_detail = 0;
							} else {
								$detail = $1;
								($dir, $detail) = ($detail, $dir);
								$w_detail = ord(lc $detail) - 97;
							}
						}
						$w_detail = $detail if $r eq 'xb';
						$dir = ord(lc $dir) - 97;
						my ($x2, $y2) =
							$self->rail_xy($r, $x1, $y1, $dir, $w_detail, $level);
						if (exists $rails->{$dir}) {
							my $levels = 1;
							$levels = 2 if grep {$_ eq $tile} qw(xM yH yT);
							$self->error("Rail %1%2: another rail in same direction already seen", $r, chr(97 + $dir)) if $rails->{$dir} >= $levels;
						}
						if ($tile) {
							push @$f, [$x2, $y2, $r, $dir, $w_detail];
						} else {
							push @{$rules->[-1]}, [$x2, $y2, $r, $dir, $w_detail];
						}
						$rails->{$dir}++ if ! $detail;
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
			my $n = scalar keys(%$rails);
			my $nmax = 0;
			$nmax = @{$self->{conn0}{$tile}} if exists $self->{conn0}{$tile};
			if (exists $self->{conn1}{$tile}) {
				my $key0 = (keys %{$self->{conn1}{$tile}})[0];
				$nmax += @{$self->{conn1}{$tile}{$key0}};
			}
			$self->error("%1 rail data seen, %2 is maximum for tile %3",
				$n, $nmax, $tile) if $n > $nmax and $tile !~ /^\|/;
			push @$rules, $f;
		}
	}
	unshift @$rules, [0, 'name', $run_name];
	# add the height of transparent planes to the level line and the tiles
	$self->level_height($rules, $planenum, $planepos);
	# find wall for the balconies, check orientation and adjust height and level
	undef $self->{line};
	return $rules;
}

sub check_marbles {
	my ($self, $tile, $dir, $detail, $items) = @_;
	my @items = grep {/^\d*o/} @$items;
	# add missing marbles where required (A, M, N, P, xF, xS)
	my @m1 = grep {$_->[5] =~ /o/} @{$self->{rules}{$tile}};
	my $colors = 'RGBSA';
	my @chk;
	for (@m1) {
		my ($m_num, $m_dir) = ($_->[5] =~ /^(\d*[^o]*)o(.)/);
		if (length $m_num > 1) { # xF
			my ($parts, $m_dir) = split '', $detail;
			$m_num = substr($m_num, 0, 1)*($parts - 1);
			$m_dir = ord($m_dir) - 97 - $dir; # absolute dir
		} else {
			next if ! $_->[6] or $_->[5] !~ /$_->[6]/;
		}
		$colors =~ s/^(.)(..)/$2$1/; # rotate RGB color names
		my $m_col = $#m1 ? $1 : 'S';
		$m_dir = chr(97 + ($m_dir + $dir) % 6);
		my $str = ($m_num || '') . "o$m_col$m_dir";
		if (@items) {
			push @chk, "o$m_col$m_dir" for 1 .. ($m_num || 1);
		} else {
			push @$items, $str;
		}
	}
	return if ! @items;
	if (! @chk) {
		$self->error("No marbles should be placed on the %1 tile", $tile);
		@$items = grep {! /^\d*o/} @$items;
		return;
	}
	# check existing marbles and add color and/or orientation
	for (grep {/o/} @$items) {
		my ($num, $str) = split /o/, $_;
		$num ||= '';
		my $color = $1 if $str and $str =~ s/([$colors])//;
		my $cdir = $1 if $str and $str =~ s/([a-f])//;
		if ($str) {
			my $what = ($color and ! $cdir) ? ' position' :
			($cdir and ! $color) ? ' color' : '';
			$self->error("Illegal%1 char %2 in %3 for marble on tile %4",
				$what, $str, $_, $tile);
			next;
		}
		if ($color and $cdir) {
			my @chk2 = grep {$_ =~ /$cdir/} @chk;
			my $numdir = ord($cdir) - 97 - $dir;
			my $out = grep {$numdir eq $_->[2]} @{$self->{rules}{$tile}};
			if (! @chk2) {
				if ($out and $self->{rules}{$tile}[0][1] eq '') {
					print loc("marble %1 on tile %2 will be started later\n",
					$_, $tile);
				} else {
					$self->error("marble on tile %1 cannot be in position %2",
						$tile, $cdir);
				}
				next;
			} else {
				my $found = shift @chk2;
				@chk = grep {$_ ne $found} @chk;
				push @chk, @chk2 if @chk2; # marbles with same dir and color
			}
		} elsif (! $color and ! $cdir) {
			@$items = (@chk, grep {! /^\d*o/} @$items);
			return;
		} elsif (! $color) {
			($_) = grep {/$cdir/} @chk;
			next if $_;
			$self->error("marble on tile %1 cannot be in position %2",
				$tile, $cdir);
			@$items = (@chk, grep {defined $_ and ! /^\d*o/} @$items);
			return;
		} elsif (! $cdir) {
			my $m = shift @chk;
			($_ = $m) =~ s/[$colors]/$color/;
		}
	}
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

=head2 resolve_z

$g->resolve_z($rail, $z_from, $z_to, $from_pos, $data);

find the best end point for the rail from $from_pos described by $rail data
using the possible z positions $z_from and $z_to.

=head2 rail_connection

$z_arrayref = $g->rail_connection($tile, $rail, $reverse);

checks if a rail connection between the starting tile $tile and the rail
$rail is possible. Returns possible z (height) values.

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

=head $g->update_meta_data($run_id);

add global meta data such as the board size to the run in the DB.

=head2 get_pos

($x, $y) = $g->get_pos($pos, $relative);

calculates the integer row and column positions from the two character
input string and checks its correctness. Both absolute notation 1..9a..z
and relative positions are handled. Returns (0, 0) on error, which is
a position outside of the board.

=head2 plane_lines

$off_xy = $g->plane_lines($lines);

searches for plane lines in the input and stores the xy offsets.
=head2 level_height

$g->level_height($rules, $off_xy, $h);

Calculates the heights of transparent planes by finding the maximum
height of the tiles below the transparent plane and adds it to the tiles
on these planes, i.e. the rule contents gets modified. The tiles are
described by the hashrefs $h and $off_xy.

=head2 header_line

($what, $value) = $g->header_line($line);

Returns the type ($what) and contents ($value) of header lines such as 'name',
'date', 'level' etc. Returns undef, if the line is not a header line

=head2 parse_run

$data = $g->parse_run($contents);

parses the input, checks it for formal correctness and returns the
parsed data.

=head2 check_marbles

$g->check_marbles($tile, $dir, $detail, $items);

Adds missing marbles where required (A, M, N, P, xF, xS) to the $items.

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

Copyright (C) 2020-2025 by Wolfgang Friebel

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.28.1 or,
at your option, any later version of Perl 5 you may have available.

=cut

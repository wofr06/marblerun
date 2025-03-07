package Game::MarbleRun::Draw;
$Game::MarbleRun::Draw::VERSION = $Game::MarbleRun::VERSION;

use v5.14;
use strict;
use warnings;
use parent 'Game::MarbleRun';
use Game::MarbleRun::I18N;
use Locale::Maketext::Simple (Style => 'gettext', Class => 'Game::MarbleRun');
use SVG;
use List::Util qw(min);

my $dbg = 0;

sub new {
	my ($class, %attr) = @_;
	my $self = {
		speed => 20,
		screen_x => $attr{screen_x} || 800,
		screen_y => $attr{screen_y} || 600,
	};
	bless $self => $class;
	# set viewport workaround for: style => {'viewport-fill' => 'white'}
	my $svg = SVG->new(width => $self->{screen_x}, height => $self->{screen_y});
	$svg->rect(width=>"100%", height=>"100%", fill=>"white");
	$self->{svg} = $svg;
	# defs section in svg
	$self->svg_defs();
	# db initialization and preloading of frequently used data
	$self->config(%attr);
}

sub svg_defs {
	my ($self) = @_;
	my $svg = $self->{svg};
	my $defs = $svg->defs();
	gradient($defs, 'mygreen','#70a000', '#70a000');
	gradient($defs, 'green_yminus','#d2d265', '#ffffff');
	gradient($defs, 'green_yplus','#ffffff', '#d2d265');
	gradient($defs, 'gray_yminus', '#d5d5d5', '#ffffff');
	gradient($defs, 'gray_yplus','#ffffff', '#d5d5d5');
	$svg->style()->cdata('path.tile {stroke: black; fill: none}');
	$svg->style()->cdata('polygon.tile {stroke: black; fill: none}');
	$svg->style()->cdata('line.tile {stroke: black; fill: none}');
	$svg->style()->cdata('text.text {font-family: Arial; text-anchor: middle}');
}

sub gradient {
	my ($defs, $name, $fromcol, $tocol) = @_;
	my $grad = $defs->tag('linearGradient',id=>$name,x1=>0,y1=>0,x2=>0,y2=>1);
	$grad->stop(offset=>"0%", style=>{"stop-color"=>$fromcol});
	$grad->stop(offset=>"100%", style=>{"stop-color" =>$tocol});
}

sub set_size {
	my ($self, $size) = @_;
	# horizontal width of a tile = 3*width3, height of a tile = 1 (6cm)
	my $width3 = $size*sqrt(1/3);
	my $middle_x = [0, 0.75, 0.75, 0, -0.75, -0.75];
	my $middle_y = [-0.5, -0.25, 0.25, 0.5, 0.25, -0.25];
	my $corner_x = [-0.5, 0.5, 1., 0.5, -0.5, -1.];
	my $corner_y = [-0.5, -0.5, 0., 0.5, 0.5, 0.];
	$_ *= $width3 for @$middle_x, @$corner_x;
	$_ *= $size for @$middle_y, @$corner_y;
	# drawing constants
	$self->{size} = $size;
	$self->{width3} = $width3;
	$self->{middle_x} = $middle_x;
	$self->{middle_y} = $middle_y;
	$self->{corner_x} = [$corner_x, [@$corner_x[2..5]], [@$corner_x[0..2,5]]];
	$self->{corner_y} = [$corner_y, [@$corner_y[2..5]], [@$corner_y[0..2,5]]];
	# diameter of rail bars, thickness of transparent planes etc.
	$self->{small_width} = 0.05*$size;
}

sub center_pos {
	my ($self, $posx, $posy) = @_;
	my $size = $self->{size};
	# offset for all drawings
	# $offset_x = $size;
	# $offset_y = 0.5*$size;
	my $x = $size + 1.5*$self->{width3}*($posx-0.5);
	my $y = $size*($posy + 0.5);
	$y += 0.5*$size if not int($posx) % 2;
	return ($x, $y);
}

sub orientations {
	my ($self, $case) = @_;
	#$case = 'extra curves';
	#$case = 'balcony';
	#$case = 'all';
	my $start = 4;
	my $shift = 7;
	my $elems = { '0.5' => 'Orientation', 2 => 'C', 4 => 'Y,S', 6 => 'X',
		8 => 'G,D', 10 => 'J,I', 12 => 'xG', 14 => 'B'};
	$case ||= '';
	if ($case eq 'balcony') {
		$elems = { '0.5' => 'Orientation', 2 => 'B'};
	} elsif ($case eq 'extra curves') {
		$start = 5;
		$shift = 9;
		$elems = { '0.5' => 'Orientation', 2 => 'xC', 4 => 'yC', 6 => 'xW',
		8 => 'yW', 10 => 'xY', 12 => 'yY', 14 => 'xX', 16 => 'yX', 18 => 'xI',
		20 => 'yI', 22 => 'xQ', 24 => 'xV'};
	} elsif ($case eq 'all') {
		$start = 6;
		$shift = 11;
		$elems = { '0.5' => 'Orientation', 2 => 'C', 4 => 'Y,S', 6 => 'X',
		8 => 'G,D', 10 => 'J,I', 12 => 'xG', 14 => 'B', 16 => 'xC',
		18 => 'yC', 20 => 'xW', 22 => 'yW', 24 => 'xY', 26 => 'yY', 28 => 'xX',
		30 => 'yX', 32 => 'xI', 34 => 'yI', 36 => 'xQ', 38 => 'xV'};
	}
	my $off_start = $start % 2 ? 0 : -0.5;
	my $off_shift = $shift % 2 ? 0 : -0.5;
	my (%label, %drawing);
	my $size_y= 0;
	my $tg = $self->{svg}->group(
		id => 'orient_txt', 'font-family'=> 'Arial', 'text-anchor' => 'middle');
	for my $k (keys %$elems) {
		if (length $elems->{$k} < 3 or $elems->{$k} =~ /,/) {
			my @e = split /,/, $elems->{$k};
			$label{$k} = join ', ', map {loc $self->{elem_name}{$_}} @e;
			$drawing{$k} = $e[0];
		} else {
			$label{$k} = loc($elems->{$k});
			$drawing{$k} = $elems->{$k};
		}
		$size_y = $k if $k > $size_y;
	}
	$size_y = 20 if $size_y < 20;
	$self->set_size(int $self->{screen_y}/($size_y + 2));
	$elems->{'0.5'} = 'Symbol';
	$self->put_text(1, $_, $elems->{$_}, {'font-size'=>''}, $tg) for sort keys %$elems;
	$self->put_text($start, $_ + $off_start, $label{$_}, {'font-size'=>''}, $tg)
		for sort keys %label;
	delete $drawing{'0.5'};
	for my $dir (0..5) {
		$self->put_text(2*$dir+$shift, 0.5, chr($dir+97), {'font-size'=>''}, $tg);
		$self->draw_tile($drawing{$_}, 2*$dir+$shift, $_+$off_shift, 0, $dir)
			for sort keys %drawing;
	}
}

sub board {
	my ($self, $board_y, $board_x, $run_id, $fill_coord, $excl, $text) = @_;
	return if ! $self->{svg};
	my $svg = $self->{svg};
	if (! $board_x) {
	# get width and height of ground plane from run
		if ($run_id) {
			my $sql = "SELECT size_x,size_y FROM run WHERE id=$run_id";
			my ($size_y, $size_x) = @{($self->{dbh}->selectall_array($sql))[0]};
			$board_x = int(($size_x + 5)/6);
			$board_y = int(($size_y + 4)/5);
		}
		if (! $board_x) {
			$self->error("Unknown board size, run_id or size_x not given");
			return;
		}
	}
	my $screen_x = $self->{screen_x};
	my $screen_y = $self->{screen_y};
	my $size = int min($screen_x/(6*$board_x + 1), $screen_y/(5*$board_y + 3));
	$self->set_size($size);
	# board attributes
	my $scale = [1., 14./15., 0.5];
	my (@hgy, @hgn);
	$hgy[0] = $self->{svg}->group(
		id => 'board_hex_gy0,', stroke => 'none', fill => 'url(#gray_yminus)');
	$hgy[1] = $self->{svg}->group(
		id => 'board_hex_gy1,', stroke => 'none', fill => 'url(#gray_plus)');
	$hgy[2] = $self->{svg}->group(
		id => 'board_hex_gy2,', stroke => 'none', fill => 'white');
	$hgn[0] = $self->{svg}->group(
		id => 'board_hex_gn0,', stroke => 'none', fill => 'url(#green_yminus)');
	$hgn[1] = $self->{svg}->group(
		id => 'board_hex_gn1,', stroke => 'none', fill => 'url(#green_yplus)');
	$hgn[2] = $self->{svg}->group(
		id => 'board_hex_gn2,', stroke => 'none', fill => 'white');
	# write the coordinate labels
	my $tg = $self->{svg}->group(
		id => 'board_txt', 'font-family'=> 'Arial', 'text-anchor' => 'middle');
	for my $x (1..6*$board_x) {
		my $y = $x % 2 ? 0 : -0.5;
		my $xx = $self->{relative} ? (($x - 1) % 6) + 1 : $x;
		my $chr = $xx < 10 ? "$xx" : chr($x+87);
		$self->put_text($x, $y, $chr, '', $tg) if ! $fill_coord;
	}
	for my $y (1..5*$board_y) {
		my $yy = $self->{relative} ? (($y - 1) % 5) + 1 : $y;
		my $chr = $yy < 10 ? "$yy" : chr($y+87);
		if (! $fill_coord) {
			$self->put_text(0, $y, $chr, '', $tg);
			$self->put_text(6*$board_x+1, $y, $chr, '', $tg);
		}
	}
	$self->put_text(3*$board_x, 5*$board_y + 0.5, $text, '', $tg) if $text;
	# draw the board
	for my $lay (0, 1, 2) {
		for my $x (1..6*$board_x) {
			for my $y (0..5*$board_y) {
				my $shape = 0;
				my $s = $hgy[$lay];
				if ($x % 2) {
					next if $y == 0;
					$s = $hgn[$lay] if $y % 5 == 1;
				} else {
					$s = $hgn[$lay] if $y % 5 == 3;
					$shape = 1 if $y == 0;
					$shape = 2 if $y == 5*$board_y;
				}
				$self->put_hexagon2($x, $y, $scale->[$lay], $s, $shape);
				my $pos = $self->num2pos($x, $y, 1);
				$self->put_text($x, $y, $pos, '', $tg) if $fill_coord and ! $shape;
			}
		}
	}
	# clear regions that are marked as to be excluded
	$size = $self->{size};
	for my $xy_excl (@$excl) {
		my ($x, $y) = (6*$xy_excl->[0], 5*$xy_excl->[1]);
		my ($x0, $y0) = $self->center_pos($x - 5, $y - 4);
		my ($x1, $y1) = $self->center_pos($x, $y);
		($x0, $y0) = ($x0 - $self->{width3}, $y0 - 0.5*$size);
		($x1, $y1) = ($x1 + $self->{width3}, $y1);
		$x0 += 0.1*$size if $xy_excl->[0] > 1;
		$x1 -= 0.1*$size if $xy_excl->[0] < $board_x;
		$_ = sprintf("%.1f", $_) for ($x0, $y0, $x1, $y1);
		my $points = $svg->get_path(x => [$x0, $x0, $x1, $x1],
			y => [$y0, $y1, $y1, $y0], -closed => 1, -type => 'polygon');
		$svg->polygon(%$points, style => {fill => 'white', stroke =>'none'},
			class =>'tile');
	}
	return 1;
}

sub put_hexagon2 {
	my ($self, $posx, $posy, $rel_size, $group, $shape) = @_;
	$shape = 0 if ! $shape or $shape > 2;
	# 0=full hex, 1=upper half, 2=lower half
	my ($xh, $yh);
	my ($x, $y) = $self->center_pos($posx, $posy);
	@$xh = map {int($x + $rel_size*$_)} @{$self->{corner_x}->[$shape]};
	@$yh = map {int($y + $rel_size*$_)} @{$self->{corner_y}->[$shape]};
	my $points = $group->get_path(x=>$xh, y=>$yh, -closed=>1, -type=>'polygon');
	$group->polygon(%$points);

}

sub draw_tile {
	my ($self, $elem, $x, $y, $z, $orient, $detail) = @_;
	return if ! $self->{svg};
	if ($elem eq 'A') {
		$self->put_Start($x, $y, $orient);
	} elsif ($elem eq 'Z') {
		$self->put_Landing($x, $y, $orient);
	} elsif ($elem eq 'xS') {
		$self->put_Spinner($x, $y);
	} elsif ($elem eq 'M') {
		$self->put_Cannon($x, $y, $orient);
	} elsif (($_) = grep {$elem eq $_} qw(K Q)) {
		$self->put_hexagon($x, $y);
		$self->put_through_line($x, $y, $orient, 0.3);
		$self->put_through_line($x, $y, $orient + 3, 0.3);
		$self->put_text($x, $y, $_, {class => 'text'});
	} elsif ($elem eq 'xA') {
		$self->put_Zipline($x, $y, ($orient+3)%6);
	} elsif ($elem eq 'xZ') {
		$self->put_Zipline($x, $y, $orient);
	} elsif ($elem eq 'H') {
		$self->put_Hammer($x, $y, $orient);
	} elsif ($elem eq 'J') {
		$self->put_Jumper($x, $y, $orient);
	} elsif ($elem eq 'xH') {
		$self->put_Spiral($x, $y, $orient, $detail);
	} elsif ($elem eq 'G') {
		$self->put_Catcher($x, $y, $orient);
	} elsif ($elem eq 'P') {
		$self->put_Splash($x, $y, $orient);
	} elsif ($elem eq 'N') {
		$self->put_Volcano($x, $y, $orient);
	} elsif ($elem eq 'D') {
		$self->put_Drop($x, $y, $orient);
	} elsif ($elem eq 'xB') {
		$self->put_BridgeTile($x, $y, $orient, $detail);
	} elsif ($elem eq 'xF') {
		$self->put_Lift($x, $y, $orient, $detail);
	} elsif ($elem eq 'xK') {
		$self->put_Catapult($x, $y, $orient);
	} elsif ($elem eq 'xQ') {
		$self->put_Looptile($x, $y, $orient);
	} elsif ($elem eq 'xT') {
		$self->put_TipTube($x, $y, $orient);
	} elsif ($elem eq 'xD') {
		$self->put_Dipper($x, $y, $orient, $detail);
	} elsif ($elem eq 'O') {
		$self->put_OpenBasket($x, $y);
	} elsif ($elem eq 'E' and not $detail) {
		$self->put_DoubleBalcony($x, $y, $orient);
	} elsif ($elem eq 'B') {
		$self->put_Balcony($x, $y, $orient);
	} elsif ($elem eq 'e') {
		$self->put_FinishLine($x, $y, $orient);
	} elsif ($elem eq '^' or $elem eq '=') {
		$self->put_TransparentPlane($x, $y, $elem);
	# height tiles
	} elsif (($_) = grep {$elem eq $_} qw(1 + L xL)) {
		$self->put_1($x, $y, $elem);
	# special cases for generic elements
	} elsif ($elem eq 'xG') {
		$self->put_BasicTile($x, $y, $orient);
	# other tiles (F,R,xM,xP,xR,xS,yH,yK,yR,yS,yT) handled here
	# (hexagon plus symbol) (K, Q also with through line)
	} else {
		$self->put_Tile($x, $y, $z, $elem, $orient, $detail);
	}
}

sub put_Tile {
	my ($self, $x, $y, $z, $elem, $orient_in, $detail) = @_;
	# a: small arc, A: large arc, C: circle H: hexagon I: straight line,
	# S: switch lever, T: text
	my %tiles = ('Straight Tile' => 'I0',
		C => 'a1A0',
		I => 'H0I0',
		S => 'A0A2S0',
		T => 'H0A0',
		U => 'H0A0A2S0',
		V => 'I0C0I3C1',
		W => 'A0I0A2',
		X => 'I0I1',
		Y => 'A0A2',
		xC => 'a0a2a4',
		xI => 'a1I0a4',
		xV => 'I0I2I4C0C1',
		xW => 'A0I0A3',
		xX => 'I0I2I4',
		xY => 'A0I0a1',
		yI => 'A1I0',
		yW => 'A2I0A5',
		yX => 'A0A1a2',
		yY => 'A2I0a4',
		yC => 'A0A3',
	);
	my $thickness = 1/6.;	# for vortex
	$orient_in ||= 0;

	my ($r, $x1, $x2, $y1, $y2, $arc);
	$self->put_hexagon($x, $y);
	my $parts = exists $tiles{$elem} ? $tiles{$elem} : 'T0';
	my @part = split //, $parts;
	while (@part) {
		my ($type, $orient2) = splice(@part, 0, 2);
		my $orient = ($orient_in + $orient2) % 6;
		if ($type eq 'a') {
			$self->put_arc($x, $y, 1, $orient);
		} elsif ($type eq 'A') {
			$self->put_arc($x, $y, 2, $orient);
		} elsif ($type eq 'C') {
			my ($r, $style);
			$r = 0.5 - $thickness if $orient2 == 0;
			$r = 7/60 if $orient2 == 1;
			$style = {fill => '#d5d5d5'} if $orient2 == 1;
			$self->put_circle($x, $y, $r, '', '', '', $style);
		} elsif ($type eq 'I') {
			my $frac = $thickness if grep {$elem eq $_} qw(V xV);
			$self->put_through_line($x, $y, $orient, $frac);
		} elsif ($type eq 'S') {
			my $scale = $self->{twoby3} if $elem eq 'U';
			$self->put_lever($x, $y, $z, $orient, $detail, $scale);
		} elsif ($type eq 'T') {
			$self->put_text($x, $y, $elem, {class => 'text'});
		} elsif ($type eq 'H') {
			$self->put_hexagon($x, $y, $self->{twoby3}, {fill=>'url(#mygreen)',
				'fill-opacity' => '0.8',});
		}
	}
}

{
	my $first_call = 1;
sub draw_rail {
	my ($self, $elem, $posx1, $posy1, $posx2, $posy2, $dir, $detail) = @_;
	#print "draw $elem $posx1,$posy1 -> $posx2,$posy2\n";
	my $svg = $self->{svg};
	return if ! $svg;
	if ($first_call) {
		my $width = "stroke-width: $self->{small_width}";
		my $width2 = "stroke-width: " . 3*$self->{small_width};
		$svg->style()->cdata("line.rail {stroke: black; $width}");
		$svg->style()->cdata("line.wall {stroke: lightblue; $width2}");
		$first_call = 0;
	}
	my $class = 'rail';
	# curved bernoulli rails
	if ($elem =~ /^[cd]$/) {
		my $inc = $elem eq 'c' ? -1 : 1;
		my ($xc, $yc) = $self->to_position($posx1, $posy1, $dir + 3 + $inc, 1);
		$self->put_arc($xc, $yc, 2, $dir - $inc - 2);
		return;
	# flextube
	} elsif ($elem eq 'xt') {
		my ($xc, $yc) = $self->to_position($posx1, $posy1, $detail + 3, 1);
		my $dx1 = $self->{middle_x}[$detail];
		my $dy1 = $self->{middle_y}[$detail];
		my ($xm, $ym) = $self->center_pos($xc, $yc);
		my $dx2 = $self->{middle_x}[$dir];
		my $dy2 = $self->{middle_y}[$dir];
		$_ = sprintf("%.1f", $_) for ($xm, $ym);
		$svg->line(x1 => int($xm + $dx1), y1 => int($ym + $dy1), x2 => int $xm,
			y2 => int $ym, class => $class);
		$svg->line(x1 => int $xm, y1 => int $ym, x2 => int($xm - $dx2),
			y2 => int($ym - $dy2), class => $class);
		return;
	}
	# straight rails
	my ($x1, $y1) = $self->center_pos($posx1, $posy1);
	my $dx = $self->{middle_x}[$dir];
	my $dy = $self->{middle_y}[$dir];
	my ($x2, $y2) = $self->center_pos($posx2, $posy2);
	#($style->{stroke}, $style->{fill}) = qw(lightblue lightblue)
	$class = 'wall' if $elem =~ /x[sml]/;
	# vertical rail
	if ($elem eq 't') {
		$x1 = $x1 + 2.5*$dx;
		$y1 = $y1 + 2.5*$dy;
	}
	$_ = sprintf("%.1f", $_) for ($x1, $y1, $x2, $y2);
	$svg->line(x1 => int($x1 - $dx), y1 => int($y1 - $dy), x2 => int($x2 + $dx),
		y2 => int($y2 + $dy), class => $class);
}
}

sub put_hexagon {
	my ($self, $posx, $posy, $rel_size, $style, $shape, $orient) = @_;
	# for shape 1 a balcony, shape 2 a double balcony is drawn
	my ($x, $y) = $self->center_pos($posx, $posy);
	$shape ||= 0;
	$rel_size ||= 1.;
	$rel_size = 0.75 if $shape;
	my $rel_size2 = 0.5;
	if (! $style) {
		$style = $shape
			? {stroke=>'lightblue', fill=>'lightblue', opacity=>'0.50'}
			: {fill => 'white'};
	}
	my $dy = 0.5*$rel_size*$self->{size};
	my $dx = $rel_size*$self->{width3};
	my $dx2 = 0.5*$dx;
	my $mx = $x - $dx2;
	my $my = $y + $dy;
	my $single = "$dx2,-$dy l-$dx2,-$dy";
	my $double = -$dx;
	# outer contour
	if ($shape == 1) {
		my $dx3 = $dx2 - $self->{small_width};
		my $dy3 = $dy - 2*$self->{small_width};
		my $dlx = $dx + $self->{small_width};
		my $dly = 4*$self->{small_width};
		$single = "$dx3 -$dy3 l$dlx 0 l0 -$dly l-$dlx 0 l-$dx3 -$dy3";
	} elsif ($shape == 2) {
		my $dx3 = $dx2 - 2*$self->{small_width};
		my $dy3 = $self->{size}*(1 - 0.95*$rel_size);
		$double = "-$dx3 0 l0 -$dy3 l$dx3 0 l$dx2 -$dy l-$dx2 -$dy l-$dx 0
			l-$dx2 $dy l$dx2 $dy l$dx3 0 l0 $dy3 l-$dx3";
	}
	my $hex = "M$mx $my l$dx 0 l$single l$double 0 l-$dx2 $dy Z";
	# holes
	my %rot = ();
	my $angle = 60*($orient || 0);
	if ($shape) {
		$dy = 0.5*$rel_size2*$self->{size};
		$dx = $rel_size2*$self->{width3};
		$dx2 = 0.5*$dx;
		$mx = $x - $dx2;
		$my = $y - $dy;
		$hex .= " M$mx $my l$dx 0 l$dx2 $dy l-$dx2 $dy l-$dx 0 l-$dx2 -$dy Z";
		$my -= $self->{size};
		$hex .= " M$mx $my l$dx 0 l$dx2 $dy l-$dx2 $dy l-$dx 0 l-$dx2 -$dy Z"
			if $shape == 2;
		$angle = 60*(($orient + 5) % 6) if $shape == 1;
		$_ = sprintf("%.1f", $_) for ($x, $y);
		%rot = (transform => "rotate($angle, $x, $y)");
	}
	$hex =~ s/(\.\d)\d+([, ])/$1$2/g;
	$self->{svg}->path(d => $hex, %rot, style => $style, class =>'tile');
	if ($shape == 1) {
	$mx = $x + 1.5*$self->{width3} - 1.5*$self->{small_width};
		$my = $y - 1.5*$self->{small_width};
		my $dlx = 0.37*$self->{size};
		my $dlx2 = $self->{small_width};
		my $dly = 3*$dlx2;
		my $dly2 = 0.5*$dly;
		my $clip = "M$mx $my l0 $dly l-$dlx 0 l-$dlx2 -$dly2 l$dlx2 -$dly2 Z";
		$clip =~ s/(\.\d)\d+([, ])/$1$2/g;
		$self->{svg}->path(d => $clip, style => {stroke => 'url(#mygreen)',
			fill => 'url(#mygreen)'}, %rot, class =>'tile');
	}
}

sub put_arc {
	my ($self, $posx, $posy, $size, $orient) = @_;
	my $svg = $self->{svg};
	my ($x, $y) = $self->center_pos($posx, $posy);
	my ($r, $x1, $x2, $y1, $y2);
	# small curve
	$r = 0.5*$self->{width3};
	if ($size == 2) {
		$r += $self->{width3};
		$orient += 4;
	}
	$x1 = $x + $self->{middle_x}[($orient) % 6];
	$y1 = $y + $self->{middle_y}[($orient) % 6];
	$x2 = $x + $self->{middle_x}[($size+$orient) % 6];
	$y2 = $y + $self->{middle_y}[($size+$orient) % 6];
	my $str = sprintf("M%.1f %.1f A%.1f %.1f 0 0 0 %.1f %.1f",
		$x1, $y1, $r, $r, $x2, $y2);
	$svg->path(d => $str, class => 'tile');
}

sub put_circle {
	my ($self, $xm, $ym, $r, $off_x, $off_y, $dir, $style_in) = @_;
	my ($x, $y) = $self->center_pos($xm, $ym);
	if ($off_x or $off_y) {
		my ($x1, $y1) = $self->center_pos($self->to_position($xm, $ym, $dir,1));
		my ($dx, $dy) = ($x1 - $x, $y1 - $y);
		($x, $y) = ($x - $off_y*$dx - $off_x*$dy, $y - $off_y*$dy + $off_x*$dx);
	}
	my $svg = $self->{svg};
	my $style = {stroke=>'black', fill=>'none'};
	if ($style_in) {
		$style->{$_} = $style_in->{$_} for keys %$style_in;
	}
	$r *= $self->{size};
	$_ = sprintf("%.1f", $_) for ($x, $y, $r);
	$svg->circle(cx=>$x, cy=>$y, r=>$r, style=>$style);
}

sub put_through_line {
	my ($self, $posx, $posy, $orient, $fraction) = @_;
	my $svg = $self->{svg};
	my ($x, $y) = $self->center_pos($posx, $posy);
	my $dx = $self->{middle_x}[($orient) % 6];
	my $dy = $self->{middle_y}[($orient) % 6];
	my ($x1, $x2, $y1, $y2) = ($x + $dx, $x - $dx, $y + $dy, $y - $dy);
	if ($fraction) {
		$x2 = $x1 + ($x2 - $x1)*$fraction;
		$y2 = $y1 + ($y2 - $y1)*$fraction;
	}
	$_ = sprintf("%.1f", $_) for ($x1, $y1, $x2, $y2);
	$svg->line(x1=>$x1, y1=>$y1, x2=>$x2, y2=>$y2, class=>'tile');
	return ($x2, $y2);
}

sub put_text {
	my ($self, $posx, $posy, $text, $attrib_in, $svg_group) = @_;
	my ($x, $y) = $self->center_pos($posx, $posy);
	my $svg = $svg_group || $self->{svg};
	my $rel_size = min($self->{screen_x}, $self->{screen_y})/600;
	my $font_size = 16/600*min($self->{screen_x}, $self->{screen_y});
	$y += 5*$rel_size;
	my $attrib = {
		'font-size' => 12*$rel_size,
	};
	if ($attrib_in) {
		for (keys %$attrib_in) {
			$attrib->{$_} = $attrib_in->{$_};
			delete $attrib->{$_} if ! $attrib->{$_};
		}
	}
	$svg->text(x => int $x, y => int $y, %$attrib)->cdata_noxmlesc($text);
}

sub put_TransparentPlane {
	my ($self, $posx, $posy, $elem) = @_;
	$elem ||= '^';
	my $num = $elem eq '=' ? 2 : 3;
	my $svg = $self->{svg};
	my ($x0, $y0) = $self->center_pos($posx, $posy);
	my $dy = $self->{size}/2.;
	my $small = 0.46;
	my $dx2 = $dy/sqrt(3);
	my $dx = 2*$dx2;
	my $ldx = $small*$dx;
	my $ldx2 = $small*$dx2;
	my $ldy = $small*$dy;
	my $m0x = $x0 - $dx2;
	my $m0y = $y0 + (2*$num -1)*$dy;
	my $m1x = $m0x + ($dx2 - $ldx2);
	my $m1y = $m0y - 2*$dy + $ldy;
	my $off_x = $dx + $dx2;
	my $smallhex = "l$ldx 0 l$ldx2 $ldy l-$ldx2 $ldy l-$ldx 0 l-$ldx2 -$ldy Z";
	my $holes;
	if ($elem eq '^') {
		for my $x (-2 .. 2) {
			for my $y (0 .. 4) {
				my $mx = $m1x + $x*$off_x;
				my $my = $m1y - 2*$y*$dy + (abs($x) == 1 ? $dy : 0);
				next if abs($x) >= 1 and ! $y or abs($x) == 2 and $y == 4;
				$holes .= " M$mx $my $smallhex";
			}
		}
	} else {
		for my $x (-1 .. 1) {
			for my $y (0 .. 2) {
				my $mx = $m1x + $x*$off_x;
				my $my = $m1y - 2*$y*$dy + (abs($x) == 1 ? $dy : 0);
				next if $x and ! abs($y);
				$holes .= " M$mx $my $smallhex";
			}
		}
	}
	my $plane = "l$dx,0 l$dx2 -$dy " x $num;
	$plane .= "l-$dx2 -$dy l$dx2 -$dy " x ($num - 1);
	$plane .= "l-$dx2 -$dy l-$dx 0 " x $num;
	$plane .= "l-$dx2 $dy l-$dx 0 " x ($num - 1);
	$plane .= "l-$dx2 $dy l$dx2 $dy " x $num;
	$plane .= "l$dx,0 l$dx2,$dy " x ($num - 1);
	$plane =~ s/(\.\d)\d+([, ])/$1$2/g;
	$holes =~ s/(\.\d)\d+([, ])/$1$2/g;
	my $style = {stroke=>'lightblue', fill=>'lightblue', opacity=>'0.5'};
	$svg->path(d=>"M$m0x $m0y $plane Z$holes", style => $style);
}

sub put_1 {
	my ($self, $x, $y, $elem) = @_;
	my $color = $elem eq '+' ? 'black' : 'gray';
	$self->put_hexagon($x, $y, .76, {fill => $color});
	$self->put_hexagon($x, $y, .5, {fill => 'url(#mygreen)'}) if $elem =~ /L/;
}

sub put_lever {
	my ($self, $x, $y, $z, $orient, $detail, $scale) = @_;
	my $svg = $self->{svg};
	$scale ||= 1.;
	my ($xc, $yc) = $self->to_position($x, $y, 0, 0.3*$scale);
	my ($xl, $yl) = $self->center_pos($xc, $yc);
	my %c = (q => 50, lg => 45, r => 22.5, ly => 375, lx => 10);
	$_ *= $self->{size}/600.*$scale for values %c; # scale coordinates
	my $q2 = 2*$c{q};
	my $q4 = 2*$q2;
	my $lg2 = 2*$c{lg};
	my $l0x = $xl - $lg2 - $q2;
	my $l0y = $yl - sqrt(0.8*$c{r}**2);
	my $l1y = $yl + sqrt(0.8*$c{r}**2);
	my $l2x = $xl + $q2 + $lg2;
	my $dx_bez = $q2 + $lg2 - 0.5*$c{lx};
	my $dy_bez = $c{ly} - $c{q};
	my $angle = 60 * (($orient + 3) % 6);
	$detail = $detail ? ($detail eq '+' ? 15 : -15) : 0;
	my ($xm, $ym) = $self->center_pos($x, $y);
	my $g = $svg->group(id => "lever$x$y$z", style => {fill => 'url(#mygreen)'},
		transform => "rotate($angle, $xm, $ym)");
	$g->path(d =>"M$l0x $l1y A$c{r} $c{r} 0 0 1 $l0x $l0y l$lg2 -$c{lg}
		q$q2 -$c{q} $q4 0 l$lg2 $c{lg} A$c{r} $c{r} 0 0 1 $l2x $l1y
		c-$dx_bez $c{q} -$dx_bez $yc -$dx_bez $c{ly} l-$c{lx} 0
		c0 -$c{ly} -$q2 -$dy_bez -$dx_bez -$c{ly}",
		transform => "rotate($detail, $xm, $l1y)");
}

sub put_Looptile {
	my ($self, $x, $y, $orient) = @_;
	$self->put_hexagon($x, $y);
	my $dy0 = 0.1;
	my $dx0 = -$dy0/sqrt(3);
	my $style = {fill => 'none', stroke=>'black'};
	$self->put_circle($x, $y, 1/3., $dx0, $dy0, $orient);
	$self->put_through_line($x, $y, $orient, 0.275);
	$self->put_through_line($x, $y, $orient + 1, 0.275);
}

sub put_Zipline {
	my ($self, $x, $y, $dir) = @_;
	$self->put_hexagon($x, $y);
	my ($x1, $y1) = $self->center_pos($x, $y);
	my $disty = 0.3;
	my $r = 0.05;
	$self->put_through_line($x, $y, $dir, 0.7);
	$self->put_middleBar($x, $y, $dir, $r, 2/3. + $r);
	$self->put_circle($x, $y, $r, 0, $disty, $dir);
}

sub put_Hammer {
	my ($self, $x, $y, $orient) = @_;
	$self->put_hexagon($x, $y);
	my $style = {stroke=>'lightgray', 'stroke-width' => 0.03*$self->{size}};
	$self->put_arrows($x, $y, $orient, 1/12., 1/16., $style);
	$self->put_circle($x, $y, 1/3.);
	$self->put_Marble($x, $y, 0, 0, $orient, 'S', 0.125);
	$self->put_middleBar($x, $y, $orient, 0.05, 2/3.+0.05);
	$self->put_middleBar($x, $y, $orient, 0.075, 1/3., 'url(#mygreen)');
	$self->put_middleBar($x, $y, $orient, 0.025, 1/6., 'url(#mygreen)');
	$self->put_through_line($x, $y, $orient, 1/6.);
	$self->put_through_line($x, $y, $orient + 3, 1/6.);
}

sub put_Jumper {
	my ($self, $x, $y, $dir) = @_;
	$self->put_hexagon($x, $y, 1, {fill => 'url(#mygreen)'});
	my $style = {stroke=>'white', 'stroke-width' => 0.07*$self->{size}};
	$self->put_arrows($x, $y, $dir, 0.23, 0.1, $style);
	my $offset = 0.125;
	$self->put_middleBar($x, $y, $dir, $offset, 1, '', 'none', 1);
	$self->put_through_line($x, $y, $dir, 1.);
}

sub put_arrows {
	my ($self, $x, $y, $dir, $offset, $size, $style) = @_;
	my $svg = $self->{svg};
	$style ||= [];
	my ($x1, $y1) = $self->center_pos($x, $y);
	my $d2 = ($dir + 2) % 6;
	my ($cx, $cy) = (2*$self->{corner_x}[0][$d2], 2*$self->{corner_y}[0][$d2]);
	my ($dx, $dy) = ($size*$cx, $size*$cy);
	my ($xd, $yd) = (0.67*$size*$cy, -0.67*$size*$cx);
	for my $i (-1., 0.5, 2.) {
		for my $j (-1, 1) {
			my ($xa, $ya) = ($x1 + $j*$cx*$offset + $i*$dy + $dx - $xd, $y1 + $j*$cy*$offset + $dy - $yd - $i*$dx);
			my ($dx1, $dy1) = ($xd - $dx, $yd - $dy);
			my ($dx2, $dy2) = (-$dx - $xd, -$dy - $yd);
			my ($dx3, $dy3) = (-$dx2, -$dy2);
			my $str = sprintf("M%.1f %.1f l%.1f %.1f l%.1f %.1f l%.1f %.1f",
				$xa,$ya,$dx1,$dy1,$dx2,$dy2,$dx3,$dy3);
			$svg->path(d => $str, style => $style);
		}
	}
}

sub put_Cannon {
	my ($self, $x, $y, $orient) = @_;
	$self->put_hexagon($x, $y);
	$self->put_hexagon($x, $y, 0.6, {fill => 'url(#mygreen)'});
	$self->put_through_line($x, $y, $orient, 0.2);
	$self->put_through_line($x, $y, $orient + 3, 0.2);
	my $length = 0.8;
	$self->put_middleBar($x, $y, $orient, $self->{r_ball}, $length, '', 'none');
}

sub put_middleBar {
	my ($self, $x, $y, $dir, $offset, $length, $fill, $stroke, $rot90) = @_;
	my $svg = $self->{svg};
	my $style = {'fill' => $fill || 'white', stroke => $stroke|| 'black'};
	my ($x1, $y1) = $self->center_pos($x, $y);
	my $d2 = ($dir + 2) % 6;
	my ($cx, $cy) = (2*$self->{corner_x}[0][$d2], 2*$self->{corner_y}[0][$d2]);
	if ($rot90) {
		($cx, $cy) = (2*$self->{middle_x}[$dir], 2*$self->{middle_y}[$dir]);
	}
	my ($dx, $dy) = ($length*$cx, $length*$cy);
	my ($xd, $yd) = (2*$offset*$cy, -2*$offset*$cx);
	my ($xdm, $ydm) = (-$xd, -$yd);
	my ($dxm, $dym) = (-$dx, -$dy);
	my ($xl, $yl) = ($x1-$dx/2-$xd/2, $y1-$dy/2-$yd/2);
	my $str = sprintf("M%.1f %.1f l%.1f %.1f l%.1f %.1f l%.1f %.1f l%.1f %.1f Z",
			$xl,$yl,$xd,$yd,$dx,$dy,$xdm,$ydm,$dxm,$dym);
	$svg->path(d => $str, style => $style);
}

sub put_arc_or_bezier {
	# draw a (closed) curve with an offset in direction dir from center x,y
	# difference between end points is length, curvature is defined by r
	my ($self, $xm, $ym, $dir, $offset, $length, $r, $closed, $bezier) = @_;
	my $svg = $self->{svg};
	$dir %= 6;
	my $d2 = ($dir + 2) % 6;
	my $z = $closed ? 'z' : '';
	my ($x, $y) = $self->center_pos($xm, $ym);
	my $dx1 = $offset*$self->{middle_x}[$dir];
	my $dy1 = $offset*$self->{middle_y}[$dir];
	($x, $y) = ($x + $dx1, $y + $dy1);
	my $dx = $length*$self->{corner_x}[0][$d2];
	my $dy = $length*$self->{corner_y}[0][$d2];
	my ($x1, $y1) = ($x - $dx, $y - $dy);
	my ($x2, $y2) = ($x + $dx, $y + $dy);
	if ($bezier) {
		my $dq1 = ($x2 + $x1)/2. - $r*$dx1;
		my $dq2 = ($y2 + $y1)/2. - $r*$dy1;
		my $str = sprintf("M%.1f %.1f Q%.1f %.1f %.1f %.1f %s",
			$x1, $y1, $dq1, $dq2, $x2, $y2, $z);
		$svg->path(d => $str, class => 'tile');
	} else {
		$r *= $self->{size};
		my $str = sprintf("M%.1f %.1f A%.1f %.1f 0 0 0 %.1f %.1f %s",
			$x1, $y1, $r, $r, $x2, $y2, $z);
		$svg->path(d => $str, class => 'tile');
	}
}

sub put_Balls {
	my ($self, $xm, $ym, $offset, $marble, $begin, $dur, $path) = @_;
	# balls are displayed in its initial state for 1s then the animation starts
	$path->[0] ||= 'M 0 0';
	my $id = $marble->[0];
	my $dir = $marble->[1] || 0;
	my $color = $marble->[2] || 'S';
	my $g = $self->put_Marble($xm, $ym, 0, $offset, $dir, $color, '', $id);
	for (my $i = 0; $i < @$path; $i++) {
		$g->animate('-method' => 'Motion', path => $path->[$i],
			dur => $dur->[$i] || 1, begin => $begin->[$i] || 0, fill=>'freeze');
	}
}

sub put_Marble {
	my ($self, $xm, $ym, $off_x, $off_y, $dir, $color, $r, $id) = @_;
	my $svg = $self->{svg};
	my $m_id = defined $id ? "radial$id" : $self->{marble_id} || 'marble000';
	$dir ||= 0;
	$color ||= 'S';
	$color = $self->{srgb}{$color};
	$r ||= $self->{r_ball};
	$r *= $self->{size};
	my ($x, $y) = $self->center_pos($xm, $ym);
	if ($off_x or $off_y) {
		my ($x1, $y1) = $self->center_pos($self->to_position($xm, $ym, $dir,1));
		my ($dx, $dy) = ($x1 - $x, $y1 - $y);
		($x, $y) = ($x + $off_y*$dx - $off_x*$dy, $y + $off_y*$dy + $off_x*$dx);
	}
	$_ = sprintf("%.1f", $_) for ($x, $y, $r);
	my $g = defined $id ? $svg->group(id => "marble$id") : $svg;
	$g->circle(cx=>$x, cy=>$y, r=>$r, style=>{fill=>$color});
	my $tag = $g->gradient(-type => 'radial', id => $m_id,
		gradientUnits => 'userSpaceOnUse', cx => $x, cy => $y, r => $r,
		fy => $y - 0.4*$r, fx => $x - 0.4*$r);
	$tag->stop(style=>{"stop-color"=>"#fff"});
	$tag->stop(style=>{"stop-color"=>"#fff"},"stop-opacity"=>0,offset=>.25);
	$tag->stop(style=>{"stop-color"=>"#000"},"stop-opacity"=>0,offset=>.25);
	$tag->stop(style=>{"stop-color"=>"#000"},"stop-opacity"=>0.7,offset=>1);
	$g->circle(cx=>$x,cy=>$y,r=>$r, style=>{fill=>"url(#$m_id)"});
	$self->{marble_id} = ++$m_id if ! defined $id;
	return $g;
}

sub put_FinishLine {
	my ($self, $x, $y, $orient) = @_;
	$self->put_circle($x, $y, 1./6.);
	$self->put_through_line($x, $y, $orient + 3, $self->{twoby3});
}

sub put_OpenBasket {
	my ($self, $x, $y) = @_;
	$self->put_circle($x, $y, 0.2);
}

sub put_Balcony {
	my ($self, $x, $y, $orient) = @_;
	$self->put_hexagon($x, $y, 1, '', 1, $orient);
	return;
}

sub put_DoubleBalcony {
	my ($self, $x, $y, $orient) = @_;
	$self->put_hexagon($x, $y, 1, '', 2, $orient);
}

sub put_BridgeTile {
	my ($self, $x, $y, $orient, $detail) = @_;
	my $thickness = (1 - $self->{twoby3})/2.;
	$self->put_hexagon($x, $y);
	$self->put_through_line($x, $y, $orient, 1);
	$self->put_Marble($x, $y, @{$self->{offset}{xB}[$_]}, $orient) for (0, 1);
}

# the following routine still needs to be improved
sub put_Catapult {
	my ($self, $x, $y, $orient) = @_;
	my $thickness = (1 - $self->{twoby3})/2.;
	$self->put_hexagon($x, $y);
	$self->put_through_line($x, $y, $orient, 0.3);
	$self->put_through_line($x, $y, $orient + 3, 0.3);
	$self->put_Marble($x, $y, @{$self->{offset}{xK}[$_]}, $orient) for (0 .. 3);
	$self->put_text($x, $y, 'xK', {class => 'text'});
}

sub put_Lift {
	my ($self, $x, $y, $orient, $detail) = @_;
	# radius of the tube = 0.14, radius/offset of the button = 0.1 / 0.36
	my $r_tube = 0.14;
	my $r_btn = 0.1*$self->{size};
	my $off_btn = 0.36;
	my $orient_out = $detail =~ /([a-f])/ ? ord($1) - 97 : $orient;
	$self->put_hexagon($x, $y);
	$self->put_circle($x, $y, $r_tube);
	$self->put_through_line($x, $y, $orient, 0.5 - $r_tube);
	$self->put_through_line($x, $y, $orient_out, 0.5 - $r_tube);
	my ($cx, $cy) = $self->center_pos($x, $y);
	$cx += 2*$off_btn*$self->{corner_x}[0][($orient+5) % 6];
	$cy += 2*$off_btn*$self->{corner_y}[0][($orient+5) % 6];
	my $svg = $self->{svg};
	$svg->circle(cx => $cx, cy => $cy, r => $r_btn,
		style => {fill=>'url(#mygreen)'});
}

sub put_Dipper {
	my ($self, $x, $y, $orient, $detail) = @_;
	my $svg = $self->{svg};
	$self->put_hexagon($x, $y);
	my $len = 0.25;
	my $r = 0.7*$self->{width3};
	my ($xc, $yc) = $self->center_pos($x, $y);
	my $dx = $self->{middle_x}[($orient-1) % 6];
	my $dy = $self->{middle_y}[($orient-1) % 6];
	my ($x1, $x2, $y1, $y2) = ($xc + $dx, $xc - $dx, $yc + $dy, $yc - $dy);
	$x2 = $x1 + ($x2 - $x1)*$len;
	$y2 = $y1 + ($y2 - $y1)*$len;
	my $x3 = int($xc + 0.5*$self->{middle_x}[($orient+3) % 6]);
	my $y3 = int($yc + 0.5*$self->{middle_y}[($orient+3) % 6]);
	$dx = $self->{middle_x}[($orient+1) % 6];
	$dy = $self->{middle_y}[($orient+1) % 6];
	my ($x4, $x5, $y4, $y5) = ($xc + $dx, $xc - $dx, $yc + $dy, $yc - $dy);
	$x5 = $x4 + ($x5 - $x4)*$len;
	$y5 = $y4 + ($y5 - $y4)*$len;
	my $str = sprintf("M%.1f %.1f L%.1f %.1f A%.1f %.1f 0 0 1 %.1f %.1f A%.1f %.1f 0 0 1 L%.1f %.1f L%.1f %.1f",
			$x1,$y1,$x2,$y2,$r,$r,$x3,$y3,$r,$r,$x5,$y5,$x4,$y4);
	$svg->path(d => $str, class => 'tile');
	$self->put_small_lever($x, $y, $orient + 3, $detail);
}

sub put_small_lever {
	my ($self, $x, $y, $orient, $detail) = @_;
	my $svg = $self->{svg};
	my %c = (r => 65, short => 4, long => 380, shift => 170);
	$_ *= $self->{size}/600. for values %c; # scale coordinates
	my $sin45 = 1./sqrt(2.); # 45 °sin = cos, tan = 1
	my ($x0, $y0) = $self->center_pos($x, $y);
	my ($x1, $y1) = ($x0 - $c{r}*$sin45, $y0 + $c{r}*$sin45 - $c{shift});
	my $x2 = $x0 + $c{r}*$sin45;
	my $y3 = $y1 + $c{r};
	my ($x4, $y4) = ($x0 + $c{short}/2., $y1 + $c{long} - $c{r}*(1+$sin45));
	my $x5 = $x0 - $c{short}/2.;
	my $y5 = $y4 - $c{r};
	my $angle = 60 * (($orient + 3) % 6);
	$detail = $detail ? ($detail eq '+' ? 15 : -15) : 0;
	my $g = $svg->group(id => "small lever$x$y", style => {fill => 'url(#mygreen)'},
		transform => "rotate($angle, $x0, $y0)");
	$g->path(d => "M$x1 $y1 A$c{r} $c{r} 0 1 1 $x2 $y1 C$x0 $y3 $x4 $y4 $x4 $y4 L$x5, $y4 C$x5 $y5 $x0 $y3 $x1 $y1", transform => "rotate($detail, $x0, $y1)");
}

sub put_Spiral {
	my ($self, $x, $y, $orient, $elems) = @_;
	$elems ||= 0;
	my $thickness = 0.1;
	$self->put_hexagon($x, $y);
	$self->put_circle($x, $y, 0.5 - $thickness, '', '', '', {fill=>'url(#mygreen)'});
	$self->put_through_line($x, $y, $orient, $thickness);
	my $orient_in = ($orient + 2*$elems - 1) % 6;
	$self->put_through_line($x, $y, $orient_in, $thickness);
	my ($xc, $yc) = $self->center_pos($x, $y);
	my $svg = $self->{svg};
	my $path = $self->helix_path($xc, $yc, ($orient_in + 3) % 6, $elems, 1);
	$svg->path(d=> $path, class => 'tile');
}

sub put_TipTube {
	my ($self, $x, $y, $dir) = @_;
	$self->put_hexagon($x, $y);
	# put green element
	my $length = 0.67;
	my $offset = 0.13;
	my $svg = $self->{svg};
	my $style = {'fill' => 'url(#mygreen)', stroke => 'none'};
	my ($x1, $y1) = $self->center_pos($x, $y);
	my $d2 = ($dir + 2) % 6;
	my ($cx, $cy) = (2*$self->{middle_x}[$dir], 2*$self->{middle_y}[$dir]);
	my ($dx, $dy) = ($length*$cx, $length*$cy);
	my ($xd, $yd) = (2*$offset*$cy, 2*$offset*$cx);
	my ($xdm, $ydm) = (-$xd, $yd);
	my ($dxm, $dym) = (-$dx, -$dy);
	my ($xl, $yl) = ($x1-$dx/2-$xd/2, $y1-$dy/2+$yd/2);
	my $str = sprintf("M%.1f %.1f l%.1f %.1f l%.1f %.1f l%.1f %.1f l%.1f %.1f Z",
			$xl,$yl,$xd,-$yd,$dx,$dy,$xdm,$ydm,$dxm,$dym);
	$svg->path(d => $str, style => $style);
	$self->put_circle($x, $y, $offset, 0., $length/2, $dir, $style);
	$self->put_through_line($x, $y, $dir, 1./6.);
	$self->put_through_line($x, $y, $dir - 1, 0.37);
}

sub put_BasicTile {
	my ($self, $x, $y, $orient) = @_;
	my $thickness = (1 - $self->{twoby3})/2.;
	$self->put_hexagon($x, $y);
	$self->put_hexagon($x, $y, $self->{twoby3}, {fill=>'white'});
	$self->put_through_line($x, $y, $orient, $thickness);
	$self->put_through_line($x, $y, $orient + 2, $thickness);
	$self->put_through_line($x, $y, $orient + 4, $thickness);
}

sub put_Spinner {
	my ($self, $x, $y) = @_;
	my $svg = $self->{svg};
	my $thickness = (1 - $self->{twoby3})/2.;
	$self->put_hexagon($x, $y);
	$self->put_hexagon($x, $y, $self->{twoby3}, {fill=>'white'});
	$self->put_through_line($x, $y, $_, $thickness) for 0 .. 5;
	$self->put_circle($x, $y, 0.4, '', '', '', {fill => 'url(#mygreen)'});
	$self->put_circle($x, $y, 0.1, '', '', '', {fill => 'url(#mygreen)'});
	my ($cx, $cy) = $self->center_pos($x, $y);
	my $r = 7./60.*$self->{size};
	my ($x2, $y2) = ($cx - $r, $cy - 0.375*$self->{size});
	my ($x3, $y3) = ($cx + $r, $cy - 0.375*$self->{size});
	my $style = {stroke=>'black', fill=>'none'};
	my $str = sprintf("M%.1f %.1f A%.1f %.1f 0 0 0 %.1f %.1f",
		$x2, $y2, $r, $r, $x3, $y3);
	$svg->path(d => $str, style => $style);
	$svg->path(d => $str, transform => "rotate($_, $cx, $cy)", style => $style)
		for (60, 120, 180, 240,300);
}

sub put_Start {
	my ($self, $x, $y, $orient) = @_;
	my $svg = $self->{svg};
	$self->put_BasicTile($x, $y, $orient);
	$self->put_hexagon($x, $y, $self->{twoby3}, {fill => 'url(#mygreen)'});
	$self->put_circle($x, $y, 0.125);
	$self->put_circle($x, $y, 0.02, '', '', '', {fill => 'black'});
	my $sign = 1 - 2*($orient % 2);
	my ($cx, $cy) = $self->center_pos($x, $y);
	my $r = 7./60.*$self->{size};
	my ($x1, $y1) = ($cx - $sign*$r, $cy - $sign*0.3*$self->{size});
	my ($x2, $y2) = ($cx - $sign*$r, $cy - $sign*0.25*$self->{size});
	my ($x3, $y3) = ($cx + $sign*$r, $cy - $sign*0.25*$self->{size});
	my ($x4, $y4) = ($cx + $sign*$r, $cy - $sign*0.3*$self->{size});
	my $s = sprintf("M%.1f %.1f L%.1f %.1f A%.1f %.1f 0 0 0 %.1f %.1f L%.1f %.1f",
		$x1, $y1, $x2, $y2, $r, $r, $x3, $y3, $x4, $y4);
	$self->{svg}->path(d => $s, fill => 'white');
	$svg->path(d => $s, fill => 'white', transform => "rotate(120, $cx, $cy)");
	$svg->path(d => $s, fill => 'white', transform => "rotate(240, $cx, $cy)");
}

sub put_Landing {
	my ($self, $x, $y, $orient) = @_;
	$self->put_BasicTile($x, $y, $orient);
	$self->put_hexagon($x, $y, $self->{twoby3}, {fill=>'url(#mygreen)'});
	$self->put_hexagon($x, $y, 0.5, {fill=>'none'});
}

sub put_Drop {
	my ($self, $x, $y, $orient) = @_;
	my $thickness = $self->{twoby3}/2.;
	my $length = 0.3;
	my $q = 3;
	$self->put_BasicTile($x, $y, $orient);
	$self->put_hexagon($x, $y, $self->{twoby3}, {fill=>'url(#mygreen)'});
	$self->put_arc_or_bezier($x, $y, $orient, $thickness, $length, $q, 1, 1);
	$self->put_through_line($x, $y, $orient, $thickness);
}

sub put_Catcher {
	my ($self, $x, $y, $orient) = @_;
	$self->put_BasicTile($x, $y, $orient);
	$self->put_hexagon($x, $y, $self->{twoby3}, {fill=>'url(#mygreen)'});
	my $len = 0.3;
	my $q = 2.;
	$self->put_arc_or_bezier($x, $y, $orient, $self->{twoby3}, $len, $q, 1, 1);
	$self->put_through_line($x, $y, $orient, 0.5);
}

sub put_Volcano {
	my ($self, $x, $y, $orient) = @_;
	$self->put_BasicTile($x, $y, $orient + 1);
	my $length = 0.22;
	$self->put_hexagon($x, $y, $self->{twoby3}, {fill=>'url(#mygreen)'});
	$self->put_arc_or_bezier($x, $y, $orient, -0.3, $length, 0.1);
	$self->put_arc_or_bezier($x, $y, $orient + 2, -0.3, $length, 0.1);
	$self->put_arc_or_bezier($x, $y, $orient + 4, -0.3, $length, 0.1);
	$self->put_through_line($x, $y, $orient, 1/6.);
}

sub put_Splash {
	my ($self, $x, $y, $orient) = @_;
	$self->put_BasicTile($x, $y, $orient);
	my $r = 1/5;
	$self->put_hexagon($x, $y, $self->{twoby3}, {fill=>'url(#mygreen)'});
	$self->put_arc_or_bezier($x, $y, $orient + 1, $self->{twoby3}, 1/3, $r);
	$self->put_arc_or_bezier($x, $y, $orient + 3, $self->{twoby3}, 1/3, $r);
	$self->put_arc_or_bezier($x, $y, $orient + 5, $self->{twoby3}, 1/3, $r);
}

sub do_run {
	my ($self, $run_id) = @_;
	my ($meta, $tiles, $rails, $marbles) = $self->fetch_run_data($run_id);
	# transform tiles into a hashref
	$self->{tiles}{$_->[0]} = [@$_[2..$#$_]] for grep {$_->[2] ne 'e'} @$tiles;
	# e is both treated as a tile and a rail
	$self->{tiles}{"e$_->[0]"} = [@$_[2..$#$_]] for grep {$_->[2] eq 'e'} @$tiles;
	# add marble and state info to marble
	my ($state, $t_pos);
	my @colors = map {$_->[2]} @$marbles;
	$self->{marble_id} = 0;
	for (@$marbles) {
		# :marble_id o direction, prepend later marbles, get removed first
		$self->{tiles}{$_->[0]}[7] = ":$self->{marble_id}o$_->[1]$_->[2]"
		. ($self->{tiles}{$_->[0]}[7] || '');
		$self->{marble_id}++;
	}
	# add reverse dir to rails
	for (@$rails) {
		if ($_->[0] eq 't') {
			$_->[7] = $_->[1];
		} elsif ($_->[0] eq 'c' or $_->[0] eq 'd') {
			$_->[7] = ($_->[1] + 2) % 6 if $_->[0] eq 'c';
			$_->[7] = ($_->[1] + 4) % 6 if $_->[0] eq 'd';
			# lower end point has to come first
			my $t1 = $_->[2];
			my $t2 = $_->[4];
			if ($self->{tiles}{$t1}[3] > $self->{tiles}{$t2}[3]) {
				($_->[2], $_->[4]) = ($_->[4], $_->[2]);
				($_->[1], $_->[7]) = ($_->[7], $_->[1]);
				$_->[0] = $_->[0] eq 'c' ? 'd' : 'c';
			}
		} elsif ($_->[0] eq 'xt') {
			$_->[7] = ($_->[6] + 3) % 6;
		} else {
			$_->[7] = ($_->[1] + 3) % 6;
		}
	}
	#print Dumper $rails;exit;
	#print Dumper $marbles;
	my $no_marbles = $self->move_marbles($rails) if $self->{motion};
	$marbles->[$_] = undef for @$no_marbles;
	return ($marbles, $no_marbles);
}

sub display_init_balls {
	my ($self, $marbles, $level) = @_;
	my %mult;
	for my $marble (@$marbles) {
		my $t_id = $marble->[0];
		next if $self->{tiles}{$t_id}[6] != $level;
		my ($sym, $x, $y) = @{$self->{tiles}{$t_id}}[0,1,2];
		my $dir = $marble->[1] || 0;
		$mult{"$sym:$dir"}++;
		my $color = $marble->[2] || 'S';
		my $off_mult = $mult{"$sym:$dir"} || 1;
		my $offset = $off_mult*($self->{offset}{$sym} || 0);
		$self->put_Marble($x, $y, 0, $offset, $dir, $color);
	}
}

sub display_balls {
	my ($self, $marbles) = @_;
	#print Dumper $marbles;
	#print Dumper $self->{xyz};exit;
	my $xyz = $self->{xyz};
	my (@begin, @dur, @path, @p);
	my $i = -1;
	for my $p (@$xyz) {
		$i++;
		next if ! exists $p->[1];
		say "marble $i" if $dbg and $self->{motion};
		($begin[$i], $dur[$i], $path[$i]) = $self->generate_path($p);
		my ($sym, $x, $y, $dir) = @{$p->[0]}[0, 1, 2, 4];
		my $off_mult = $sym eq 'M' ? 2 : 1;
		$self->put_Balls($x, $y, $off_mult*$self->{offset}{$sym},
			[$i, $dir, $marbles->[$i][2]], $begin[$i], $dur[$i], $path[$i]);
	}
	# display the balls which have not moved
	#print Dumper $self->{tiles};
	for my $t_id (grep {$self->{tiles}{$_}[7] and $self->{tiles}{$_}[7] =~ /o/}
		keys %{$self->{tiles}}) {
		my ($sym, $x, $y) = @{$self->{tiles}{$t_id}}[0,1,2];
		my $state = $self->{tiles}{$t_id}[7];
		my %mult;
		for my $str (split /:/, $state) {
			next if ! $str;
			my ($m_id, $dir, $color) = ($str =~ /^(\d+)o(.)(.)/);
			next if defined $xyz->[$m_id][0];
			say "$sym at $x,$y marble $m_id dir $dir, color $color $str" if $dbg and $self->{motion};
			$mult{$dir}++;
			my $desc = [$m_id, $dir, $color];
			$self->put_Balls($x, $y, $mult{$dir}*$self->{offset}{$sym}, $desc);
		}
	}
}

sub get_moving_marbles {
	my ($self, $marbles) = @_;
	my $xT_delay = 0.8;
	my $same_pos_delay = 90;
	for my $id (grep {$self->{tiles}{$_}[7]} keys %{$self->{tiles}}) {
		my $t = $self->{tiles}{$id};
		next if ($t->[8] || 0) > $self->{ticks}; ###
		my $t_dir = $t->[4];
		for my $rule (@{$self->{rules}{$t->[0]}}) {
			# a rule with an outgoing marbe exists
			next if ! defined $rule->[6] or $rule->[6] !~ /o/;
			my %dirs;
			# calculate possible marble dirs from the marble on the tile
			for my $str (grep {$_} split /:/, $t->[7]) {
				my ($m_dir) = ($str =~ /\d+o(.).$/);
				$m_dir eq 'M' ? $dirs{M}++ : $dirs{($m_dir - $t_dir) % 6}++;
			}
			my $match = 1;
			my $cond = $rule->[5];
			(my $num_r) = ($cond =~ /(\d?)o./);
			$num_r ||= 1;
			# check if conditionis fulfilled
			while ($cond =~ s/(\d?)o(.)//) {
				my $num = $1 || 1;
				$match = 0 if ! exists $dirs{$2} or ($dirs{$2} < $num
					or ($t->[0] eq 'M' and $dirs{$2} != $num));
			}
			if ($match) {
				my $inc = 1;
				my $dir = (substr($rule->[6], -1, 1) + $t_dir) % 6;
				# reshuffle marbles (last in, first out with dir corrected)
				if ($t->[0] eq 'xT') {
					my $dir_in = ($dir - 1) % 6;
					$t->[7] =~ s/o$dir_in/o$dir/g;
					$t->[7] =~ s/^(:[^:]+)(:[^:]+)(:[^:]+)/$3$2$1/;
				}
				# now no marble at orientation $dir
				while ($t->[7] =~ s/:(\d+)o$dir(.)//) {
					if ($t->[0] eq 'xT') {
						$inc += $xT_delay;
						$self->{ticks} += $xT_delay;
					}
					my ($num, $color) = ($1, $2);
					$marbles = [grep {$_->[0] != $num} @$marbles];
					say "$num: start marble at xy=$t->[1],$t->[2] t=",
						$self->{ticks} + $inc, " $self->{color}{lc $color}",
						" ($self->{dirchr}[$dir])" if $dbg;
					# id sym x y z dir_in dir_out total_time inc_time len energy
					my $len = 0.5;
					$len -= $self->{offset}{$t->[0]}
						if exists $self->{offset}{$t->[0]};
					my $e = 10*$t->[3] + 5;
					push @$marbles, [$num, $id, undef, @$t[1..3],
						undef, $dir, $self->{ticks}+$inc, 0, $color, $len, $e];
					# inhibit emitting new marbles for 90 ticks
					$inc += $same_pos_delay if $rule->[2] ne '';
					my $left = $t->[7] =~ s/(o$dir)/$1/g;
					$num_r-- if $t->[0] eq 'xT';
					last if ! $left or $left < $num_r;
				}
			}
		}
	}
	#print Dumper $marbles,$self->{ticks};
	#print Dumper $self->{tiles};
	return $marbles;
}

sub move_marbles {
	my ($self, $rails) = @_;
	my ($marbles, $no_marbles);
	$self->{ticks} = 0;
	do {{
		$marbles = $self->get_moving_marbles($marbles);
		my $m = (sort {$a->[8] <=> $b->[8]} @$marbles)[0];
		my $m0 = $m->[0];
		last if ! defined $m0;
		$self->{ticks} = $m->[8];
		if (! defined $m->[7]) {
			say "$m0: marble path finished or paused" if $dbg;
			$marbles = [grep {$_->[0] != $m0} @$marbles];
			next;
		}
		my $m_dir = $m->[7];
		my $t_id = $m->[1];
		my $t_name = $self->{tiles}{$t_id}[0];
		# find outgoing connecting rail
		my @out = grep {$t_id == $_->[2] and $m_dir eq $_->[1]} @$rails;
		@out = () if $self->{rules}{$t_name}[0][2] eq 'F';
		#say "$m0: search for rail in direction $m_dir connected to tile $t_id";
		if (defined $out[0]) {
			say "$m0: rail out $out[0]->[0] found, dir $out[0]->[1]" if $dbg;
			say "$m0: next tile $self->{tiles}{$out[0]->[4]}[0] in dir = $out[0]->[7]" if $dbg;
			$m = $self->update_marble($m, $out[0]->[4], $out[0]->[7], $out[0]);
		} else {
			# find incoming connecting rail
			my @in = grep {$t_id == $_->[4] and $m_dir eq $_->[7]} @$rails;
			if (@in) {
				$t_name = $self->{tiles}{$in[0]->[4]}[0];
				@in = () if $self->{rules}{$t_name}[0][2] eq 'F';
			}
			if (defined $in[0]) {
				say "$m0: rail in $in[0]->[0] found, dir $in[0]->[7]" if $dbg;
				say "$m0: next tile $self->{tiles}{$in[0]->[2]}[0] in_dir = $in[0]->[1]" if $dbg;
				$m = $self->update_marble($m, $in[0]->[2], $in[0]->[1], $in[0]);
			} else {
				# find neighboring tile
				my $tiles = $self->{tiles};
				$m_dir = ($m_dir + 3) % 6 if $t_name eq 'F';
				my $d = $t_name eq 'xK' ? 2 : 1;
				my ($x, $y) = $self->to_position($m->[3], $m->[4], $m_dir, $d);
				my $z = $m->[5];
				$z += $self->{rules}{$t_name}[0][4] if $t_name eq 'xK';
				$m_dir = 'M' if $t_name eq 'xK';
				my $next = $self->tile_rule($x, $y, $z, $m_dir);
				if ($next) {
					my $tile = $tiles->{$next};
					say "$m0: next tile $tile->[0], xyz=@$tile[1..3], dir ",
						$tile->[4] || -1 if $dbg;
					my $new_dir = $m->[7] eq 'M' ? $m->[7] : ($m->[7] + 3) % 6;
					$new_dir = $m->[7] eq 'M' ? $m->[7] : ($m->[7] + 3) % 6;
					$new_dir = $m->[7] if $t_name eq 'F';
					$m = $self->update_marble($m, $next, $new_dir);
				} else {
					say "$m0: no connection xyz=$x $y $z dir $m_dir" if $dbg;
					push @$no_marbles, $m0 if ! defined $self->{xyz}[$m0];
					$marbles = [grep {$_->[0] != $m0} @$marbles];
				}
			}
		}
		$self->{ticks} = $m->[8];
	}} while defined $marbles->[0];
	return $no_marbles;
}

sub tile_rule {
	my ($self, $x, $y, $z, $dir) = @_;
	my $t = $self->{tiles};
	for (grep {$self->{rules}{$t->{$_}[0]}} keys %$t) {
		next if $x != $t->{$_}[1] or $y != $t->{$_}[2];
		say "   xy check ok" if $dbg;
		my $t_id = $_;
		my $tile_z = $t->{$t_id}[3];
		if ($t->{$t_id}[0] eq 'xH' and $dir ne 'M') {
			$tile_z += $t->{$t_id}[5];
			my $in = spiral_dir($t->{$t_id}[4], $t->{$t_id}[5]);
			next if $dir != ($in + 3) % 6;
		} elsif ($t->{$t_id}[0] eq 'xF') {
			$self->{rules}{xF}[0]= ['xF', 0, ord($2) - 97, 0, 7*($1 - 1), 'o0'x (3*($1 - 1)), 'o0']
				if $t->{$t_id}[5] =~ /(^\d)([a-f])/;
		}
		for (@{$self->{rules}{$t->{$t_id}[0]}}) {
			say "   zcheck marble z=$z, next tile_z=$tile_z, dir=$dir rule: $_->[3] -> $_->[4]" if $dbg;
			if ($dir eq 'M') {
				next if $_->[1] ne 'M';
				next if $_->[5] !~ /o/ and abs($_->[5]) > abs($z - $tile_z);
			} elsif ($_->[4] < 0) {
				next if $tile_z - $z < $_->[4];
			} else {
				my $zin = $_->[3] =~ /^\d+$/ ? $z - $_->[3] : $z;
				# allow for a step of 1 on the path
				next if $zin != $tile_z and $zin != $tile_z + 1;
			}
			say "   tile $t->{$t_id}[0] ok" if $dbg;
			return $t_id;
		}
		say "   tile $t->{$t_id}[0] failed" if $dbg;
	}
}

sub update_marble {
	my ($self, $marble, $tile_id, $dir, $rail) = @_;
	my $m_id = $marble->[0];
	my $t = $self->{tiles}{$marble->[1]};
	say "$m_id: ticks=$self->{ticks} from $t->[0] xyz=@$t[1,2,3] dir $marble->[7]" if $dbg;
	if (! exists $self->{xyz}[$m_id] or ($self->{xyz}[$m_id][-1][4] ne 'M' and $self->{xyz}[$m_id][-1][4] < 0)) {
		say "$m_id: start marble at $self->{ticks}" if $dbg;
		push @{$self->{xyz}[$m_id]}, [@$t[0 .. 3], $marble->[7], $t->[5],
			$self->{ticks}];
	}
	$t = $self->{tiles}{$tile_id};
	say "$m_id: to $t->[0] xyz=@$t[1,2,3] dir $marble->[7]" if $dbg;
	if ($rail) {
		$marble->[2] = $rail->[0];
		my $len = min($self->{rail}{$rail->[0]}[1] - 1, 1);
		if ($rail->[0] =~ /^[uv]$/) {
			$len /=2;
			($t->[1], $t->[2]) = $self->to_position($t->[1], $t->[2], $dir, 2);
			$dir = 'M';
		}
		#my $special = $self->{rail}{$rail->[0]}[4];
		#$len = $special eq 'fast' ? $len/2 : $special eq 'slow' ? $len*2 : $len;
		$marble->[8] += 10*$len;
		$self->{ticks} = $marble->[8];
		$marble->[7] = ($marble->[7] + 3) % 6 if $rail->[0] eq 't';
		push @{$self->{xyz}[$m_id]}, [$rail->[0], @$t[1,2,3], $marble->[7],
			$t->[5], $self->{ticks}];
	}
	$marble->[1] = $tile_id;
	my $t_name = $self->{tiles}{$tile_id}[0];
	$marble->[2] = undef;
	@$marble[3,4,5] = @{$self->{tiles}{$tile_id}}[1,2,3];
	$marble->[6] = $dir;
	$marble->[7] = $self->next_dir($marble);
	my $new_dir = $marble->[6];
	if ($marble->[6] ne 'M') {
		$new_dir = ($marble->[6] - 3) % 6;
	} elsif ($self->{tiles}{$tile_id}[0] eq 'xH') {
		# mark direction (+ 600) as coming from middle (for marble animation)
		$new_dir = $self->{tiles}{$tile_id}[4] + 2*$self->{tiles}{$tile_id}[5] + 2 + 600;
	}
	# adjust z of connecting tile if it connects to Helix
	if ($self->{tiles}{$tile_id}[0] eq 'xH' and $self->{xyz}[$m_id][-1][0] =~ /[a-w]$/) {
		$self->{xyz}[$m_id][-1][3] += $self->{tiles}{$tile_id}[5];
	}
	push @{$self->{xyz}[$m_id]}, [@{$self->{tiles}{$tile_id}}[0..3],
		$new_dir, $self->{tiles}{$tile_id}[5], $self->{ticks}];
	my $balls = 0;
	if (! defined $marble->[7]) {
		$balls = $self->{tiles}{$tile_id}[7] || '';
		my $color = $marble->[10];
		if ($self->{tiles}{$tile_id}[0] eq 'M') {
			$balls = $balls =~ s/o$dir/o$dir/g;
			$self->{tiles}{$tile_id}[7] = ":$marble->[0]o$marble->[6]$color".($self->{tiles}{$tile_id}[7] || '');
		} else {
			$balls = ($balls =~ tr /:/:/);
			$self->{tiles}{$tile_id}[7] .= ":$marble->[0]o$marble->[6]$color";
		}
		push @{$self->{xyz}[$m_id]}, [@{$self->{tiles}{$tile_id}}[0..3],
			-1 - $balls, $self->{tiles}{$tile_id}[5], $self->{ticks}];
	}
	my $len = $self->path_length($tile_id, $dir, $marble->[7]);
	$marble->[8] += 10*$len;
	$self->{ticks} = $marble->[8];
	return $marble;
}

sub path_length {
	my ($self, $t_id, $in, $out) = @_;
	my $t = $self->{tiles}{$t_id};
	my $sym = $t->[0];
	my %len = (A => 0.25, M => 2*$self->{r_ball},
		N => 11./24. + $self->{r_ball}, P => 5./12. + $self->{r_ball}, Q => 3,
		Z => 0.5, xA => 0.7, xK => 2.5, xS => 0.125, xT => 0.5, xZ => 0.7);
	return 0.5 if ! $out;
	return 0.5 if $in eq 'M' or $out eq 'M';
	my $pi = 3.1416;
	my $pi_by_sqrt3 = $pi/sqrt(3.);
	$len{$sym} = 1 + 0.5*$t->[5] if $sym eq 'xB';
	$len{$sym} = 2*$pi*0.4/3. + 2*$pi*0.21*$t->[5]/3. if $sym eq 'xH';
	$len{$sym} = 2*$pi*0.33 + 0.6 if $sym eq 'xQ';
	return $len{$sym} if exists $len{$sym};
	my $diff = abs($in - $out);
	return 1 if $diff == 3;
	return $pi_by_sqrt3/2. if $diff == 2 or $diff == 4;
	return $pi_by_sqrt3/3. if $diff == 1 or $diff == 5;

}

sub spiral_dir {
	my ($dir, $elems, $out) = @_;
	return ($dir - 2*$elems + 1) % 6 if defined $out;
	return ($dir + 2*$elems - 1) % 6;
}

sub move_switch {
	my ($self, $t) = @_;
	my $svg = $self->{svg};
	my $id = "$t->[3]_$t->[4]_$t->[5]";
	return;
}
sub next_dir {
	my ($self, $marble) = @_;
	my $t = $self->{tiles}{$marble->[1]};
	# outgoing direction for spiral is stored in incoming dir
	if ($t->[0] eq 'xH') {
		my $in_dir = spiral_dir($t->[4], $t->[5]);
		return $t->[4] if $marble->[6] eq 'M' or $marble->[6] == $in_dir;
		return undef;
	}
	#print "tile", Dumper $t, $marble, $marble->[6],$t->[4] if $t->[0] eq 'S';
	for my $rule (@{$self->{rules}{$t->[0]}}) {
		if ($t->[0] eq 'xF') {
			$rule = ['xF', 0, ord($2) - 97, 0, 7*($1 - 1), 'o0'x (3*($1 - 1)), 'o0']
				if $t->[5] =~ /(^\d)([a-f])/;
		}
		say "$marble->[0]: rule $rule->[0] $rule->[1] -> $rule->[2]" if $dbg;
		# handle state, set new state;
		if (defined $rule->[6] and $rule->[6] =~ /^[0-5]$/) {
			# store initial state if not yet done
			if (! defined $t->[8] and defined $t->[5]) {
				($t->[8] = $t->[5]) =~ tr/-+/01/ if $t->[5] =~ /^[+-]$/;
			}
			my $state = $t->[8] || 0;
			next if $state ne $rule->[5];
			$t->[8] = $rule->[6];
			$self->move_switch($t) if $t->[0] =~ /^[SU]$/;
			#say $t->[8] if $t->[0] eq 'S';
			say "state $state -> $rule->[6]" if $dbg;
		}
		# outgoing direction: middle
		if ($rule->[2] eq 'M') {
			return 'M';
		# incoming direction: middle
		} elsif ($rule->[1] eq 'M') {
			return ($rule->[2] + $t->[4]) % 6 if $rule->[2] =~ /^[0-5]$/;
		# outgoing direction: flying (no connection for rails)
		} elsif ($rule->[2] =~ /^[FR]$/) {
			$marble->[5] += $rule->[3] if $rule->[1] eq 'F';
			$marble->[5] += ($rule->[4] - $rule->[3]) if $rule->[4] =~ /^\d$/;
			return $rule->[2] eq 'F' ? $marble->[7] : $marble->[6];
		} elsif ($marble->[6] =~ /\d/ and ($rule->[1] eq 'F' or ($rule->[1] =~ /^[0-5]$/
			and $rule->[1] == ($marble->[6] - $t->[4]) % 6))) {
			# update z if required
			$marble->[5] += $rule->[4] if $rule->[4] > 0;
			return ($rule->[2] + $t->[4]) % 6 if $rule->[2] =~ /^[0-5]$/;
		}
	}
	return undef;
}

sub generate_path {
	my ($self, $xyz) = @_;
	my ($x0, $y0) = $self->center_pos($xyz->[0][1], $xyz->[0][2]);
	# start tile needs an offset in marble direction
	#print Dumper $xyz;
	my ($paths, $starts, $lengths);
	my $sym = $xyz->[0][0];
	if (exists $self->{offset}{$sym}) {
		#distance to the edge
		my $offset = $self->{offset}{$sym};
		$offset *= 2 if $sym eq 'M';
		my $dir = $xyz->[0][4];
		my ($dx, $dy) = (2*$self->{middle_x}[$dir], 2*$self->{middle_y}[$dir]);
		$x0 += $offset*$dx;
		$y0 += $offset*$dy;
	}
	my $path = "M 0 0";
	my $start;
	for (my $i = 0; $i < @$xyz; $i++) {
		$start = $xyz->[$i][6] || 0 if ! defined $start;
		my ($sym, $xc, $yc, $z, $dir, $detail) = @{$xyz->[$i]};
		last if ! $sym;
		next if exists $xyz->[$i + 1] and $xyz->[$i + 1][4] ne 'M' and $xyz->[$i + 1] < 0;
		say " path sym $sym xyz=$xc $yc $z dir=$dir tics=$xyz->[$i][6]" if $dbg;
		my ($x, $y) = $self->center_pos($xc, $yc);
		if ($sym eq 'xH') {
			my $elems = $detail;
			$path .= $self->helix_path($x - $x0, $y -$y0, $dir, $elems);
		} elsif ($sym eq 'xQ') {
			my $d2 = ($dir - 1)%6;
			my $off = 0.18;
			my $r = 0.33*$self->{width3};
			my $r3 = 3*$r;
			my ($dx, $dy) = ($self->{middle_x}[$dir], $self->{middle_y}[$dir]);
			my ($dx2, $dy2) = ($self->{middle_x}[$d2], $self->{middle_y}[$d2]);
			my ($x1, $y1) = ($x - $off*$dx - $x0, $y - $off*$dy - $y0);
			my ($x2, $y2) = ($x - $off*$dx2 - $x0, $y - $off*$dy2 - $y0);
			my ($x3, $y3) = ($x - $dx2 - $x0, $y - $dy2 - $y0);
			$path .= " A $r3 $r3 0 0 1 $x2 $y2 A $r $r 1 1 0 $x1 $y1 A $r3 $r3 0 0 1 $x3 $y3";
		} elsif ($dir eq 'M') {
			$path .= " L " . ($x - $x0) . ' ' . ($y - $y0);
		} elsif ($dir < 0 || $dir eq '') {
			my $balls = -$dir || 1;
			$dir = $xyz->[$i - 1][4];
			$dir = $xyz->[$i - 2][4] if $dir eq 'M';
			$dir = ($dir + 3) % 6;
			say "finish: at $sym xyz=$xc $yc $z dir=$dir" if $dbg;
			my $frac = 3*$self->{r_ball};
			$frac = -3*$self->{r_ball} if $sym eq 'xA';
			$frac = 3*$self->{r_ball} if $sym eq 'xZ';
			# end of path finish line and tiptube (e, xT)
			if ($sym =~ /^e$|^xT$/) {
				$frac = 4*$self->{r_ball}*(($balls -1)%3);
				if ($sym eq 'xT') {
					$frac += $self->{offset}{$sym};
					$dir = ($dir + 1) % 6;
				}
			} elsif ($sym eq 'M') {
				$frac = 4*$self->{r_ball}*$balls;
			} elsif ($sym eq 'Z') {
			# end of path landing (Z)
				$dir = (2*$balls + int($balls/3)) % 6;
			}
			my ($dx, $dy) = ($self->{middle_x}[$dir], $self->{middle_y}[$dir]);
			my ($xto, $yto) = ($x - $x0 + $frac*$dx, $y - $y0+ $frac*$dy);
			$path .= " L $xto $yto";
			$path =~ s/(\.\d)\d+ /$1 /g;
			push @$paths, $path;
			push @$starts, ($start)/$self->{speed};
			push @$lengths, (($xyz->[$i][6] || 0) - $start)/$self->{speed};
			$path = " M $xto $yto";
			$start = undef;
		} elsif ($sym =~ /x?[a-w]$/) {
			last if ! exists $xyz->[$i+1];
			my ($x, $y) = $self->center_pos($xyz->[$i+1][1], $xyz->[$i+1][2]);
			$dir = ($dir - $self->{rail}{$sym}[4]) % 6 if $sym =~ /^[cd]$/;
			my ($dx, $dy) = ($self->{middle_x}[$dir], $self->{middle_y}[$dir]);
			$x = $x - $x0 - $dx;
			$y= $y - $y0 - $dy;
			if ($sym =~ /^[cd]$/) {
				my $r = 1.5*$self->{width3};
				my $flip = $self->{rail}{$sym}[4] > 0 ? 0 : 1;
				$path .= " A $r $r 0 0 $flip $x $y";
			} elsif ($sym eq 'xt') {
				$path .= " l $dx $dy";
				my $out = $xyz->[$i+1][4];
				($dx, $dy) = ($self->{middle_x}[$out], $self->{middle_y}[$out]);
				$path .= " l $dx $dy";
			} elsif ($sym eq 't') {
				$dx = 0.5*$dx;
				$dy = 0.5*$dy;
				$path .= " L " . ($x - $dx) . ' ' . ($y - $dy);
				$path .= " l $dx $dy";
			} else {
				$path .= " L $x $y";
			}
		} elsif ($sym eq 'V') {
			my $r = 0.2*$self->{size};
			my $turns= 2.5;
			$path .= spiral_path($x - $x0, $y -$y0, $r, $turns, $dir);
		} elsif ($sym !~ /^[ADMZ]$|^xT$/) {
			my $out = $xyz->[$i+1][4];
			$out = ($out + 3) % 6 if defined $xyz->[$i+1][0] and $xyz->[$i+1][0] eq 't';
			$out = $dir if ! defined $out or $out !~ /^\d$/;
			my ($dx, $dy) = ($self->{middle_x}[$out], $self->{middle_y}[$out]);
			$x += $dx - $x0;
			$y += $dy - $y0;
			my $dir_diff = ($out - $dir - 3) % 6;
			if (not $dir_diff % 3) {
				$path .= " L $x $y";

				$path .= " L " . ($x - 2*$dx) . ' ' . ($y - 2*$dy) . " L $x $y" 
					if $sym eq 'Q' or $sym eq 'F'; # simulate looping
			} else {
				my $r = (($dir_diff % 2) ? 0.5 : 1.5)*$self->{width3};
				my $flip = $dir_diff < 3 ? 0 : 1;
				$path .= " A $r $r 0 0 $flip $x $y";
			}
		}
	}
	if (! $paths) {
		push @$paths, $path;
		push @$starts, ($start)/$self->{speed};
		push @$lengths, (($xyz->[-1][6] || 0) - $start)/$self->{speed};
	}
	return ($starts, $lengths, $paths);
}

sub helix_path {
	my ($self, $x, $y, $dir, $elems, $hide) = @_;
	my $thickness = 0.1;
	my $out = ($dir + 4 - 2*$elems) % 6;
	my $length = 0.4;
	my $d1 = ($dir + 3) % 6;
	my $d2 = ($dir + 2) % 6;
	my $d3 = ($dir + 1) % 6;
	my $d4 = ($out + 2) % 6;
	my $d5 = ($out + 1) % 6;
	my $d6 = $out % 6;
	my $dx1 = $self->{middle_x}[$d1]*(1-2*$thickness);
	my $dy1 = $self->{middle_y}[$d1]*(1-2*$thickness);
	my $dx2 = $length*$self->{middle_x}[$d2];
	my $dy2 = $length*$self->{middle_y}[$d2];
	my $dx3 = $length*$self->{corner_x}[0][$d3];
	my $dy3 = $length*$self->{corner_y}[0][$d3];
	my $dx4 = $length*$self->{corner_x}[0][$d4];
	my $dy4 = $length*$self->{corner_y}[0][$d4];
	my $dx5 = $length*$self->{middle_x}[$d5];
	my $dy5 = $length*$self->{middle_y}[$d5];
	my $dx6 = $self->{middle_x}[$d6]*(1-2*$thickness);
	my $dy6 = $self->{middle_y}[$d6]*(1-2*$thickness);
	my ($x1, $y1) = ($x + $dx1, $y + $dy1);
	($x1, $y1) = ($x, $y) if $dir > 600 and ! $hide;
	my ($x2, $y2) = ($x + $dx2, $y + $dy2);
	my ($x3, $y3) = ($x - $dx3, $y - $dy3);
	my ($x4, $y4) = ($x - $dx4, $y - $dy4);
	my ($x5, $y5) = ($x + $dx5, $y + $dy5);
	my ($x6, $y6) = ($x + $dx6, $y + $dy6);
	my $r = 0.21*$self->{size};
	my $r2 = 0.4*$self->{size};
	my $L_or_M = $hide ? 'M' : 'L';
	my $path = "$L_or_M $x1 $y1 A $r2 $r2 0 0 1 $x2 $y2" ;
	$path .= "$L_or_M $x2 $y2 A $r $r 1 0 0 $x5 $y5" if $elems <=3;
	$path .= "$L_or_M $x2 $y2 A $r $r 1 1 0 $x3 $y3" if $elems > 3;
	if (! $hide) {
		for (my $i=0; $i < int(($elems - 4)/3); $i++) {
			$path .= "$L_or_M $x3 $y3 A $r $r 1 1 0 $x4 $y4";
			$path .= "$L_or_M $x4 $y4 A $r $r 1 0 0 $x3 $y3";
		}
		my $flip = ($elems % 3) == 1 ? 0 : 1; 
		$path .= "$L_or_M $x3 $y3 A $r $r 1 $flip 0 $x5 $y5" if $elems > 3;
	}
	$path .= "$L_or_M $x5 $y5 A $r2 $r2 0 0 1 $x6 $y6" if $elems <=3 or ! $hide;
	return $path;
}

sub spiral_path {
	my ($xm, $ym, $r, $turns, $dir) = @_;
	my ($old_th,$new_th, $old_r, $new_r, $old_p, $new_p, $old_slp, $new_slp);
	my $pi = 3.1416;
	my $th_step = -2*$pi*0.1; # turn direction
	my $b = -$r/$turns/$pi/2;
	$old_th = $new_th = $pi*$dir/3 - $pi/4; # turn direction
	my $end_th = -2*$turns*$pi + $old_th; # turn direction
	$old_r = $new_r = $r + $b*$new_th;
	$old_p = [0, 0];
	$new_p = [$xm + $new_r*cos($new_th), $ym + $new_r*sin($new_th)];
	$old_slp = $new_slp = ($b*sin($old_th) + ($r + $b*$new_th)*cos($old_th))/
		($b*cos($old_th) - ($r + $b*$new_th)*sin($old_th));
	my $path = " L$new_p->[0] $new_p->[1]";
	while ($old_th > $end_th - $th_step) { # turn direction
		($old_th, $new_th) = ($new_th, $new_th + $th_step);
		($old_r, $new_r) = ($new_r, $r - $b*$new_th); # turn direction
		($old_p, $new_p) = ($new_p,
			[$xm + $new_r*cos($new_th), $ym + $new_r*sin($new_th)]);
		($old_slp, $new_slp) = ($new_slp,
			($b*sin($new_th) + ($r + $b*$new_th)*cos($new_th)) /
			($b*cos($new_th) - ($r + $b*$new_th)*sin($new_th)));
		my $old_ic = -($old_slp*$old_r*cos($old_th) - $old_r*sin($old_th));
		my $new_ic = -($new_slp*$new_r*cos($new_th) - $new_r*sin($new_th));
		my $x0 = ($new_ic - $old_ic)/($old_slp - $new_slp);
		my ($x_ctrl, $y_ctrl) = ($xm + $x0, $ym + $old_slp*$x0 + $old_ic);
		$path .= " Q$x_ctrl $y_ctrl $new_p->[0] $new_p->[1]";
	}
	return $path;
}

sub emit_svg {
	my ($self, $name, $level) = @_;
	my $svg = $self->{svg};
	$self->{outputfile} = $name if ! $self->{outputfile};
	return if ! $self->{svg} or ! defined $self->{outputfile};
	my $svgfile = $self->{outputfile} or
		$self->get_file_name('', 'svg', loc("ENTER to exit"), 0);;
	$svgfile =~ s/\.svg$// if defined $svgfile;
	$self->{outputfile} = $svgfile;
	return if ! defined $svgfile or $svgfile =~ /^\s*$/;
	$svgfile .="_$level" if defined $level and $level ne '';
	$svgfile .= '.svg';
	if ($svgfile and -r $svgfile) {
		my $yn = $self->prompt(loc("File %1 existing, overwrite it?",$svgfile));
		my $Y = loc('Y');
		return '' if $yn !~ /^[y$Y]/i;
	}
	open F, ">$svgfile" or die "$svgfile: $!\n";
	print F $svg->xmlify;
	close F;
	say loc("Created %1", $svgfile);
}
1;
__END__
=encoding utf-8
=head1 NAME

Game::MarbleRun::Draw - Create SVG visualizations from marble runs

=head1 SYNOPSIS

  #!/usr/bin/perl
  use Game::MarbleRun::Draw;
  $g = Game::MarbleRun::Draw->new();
  $g->board(2, 1);
  $g->put_Tile(6, 5, 'W', 3);	# a 3 in 1 tile
  $g->put_Tile(5, 4, 'C', 2);	# a curve
  $g->emit_svg('board_with_2_elems');
  $g2 = Game::MarbleRun::Draw->new();
  $g2->orientations($case);
  $g2->emit_svg('orient');

=head1 DESCRIPTION

Game::MarbleRun::Draw provides methods to visualize a track from
the database or to draw a GraviTrax® board with elements.

To store descriptions of marble runs in the DB methods from
Game::MarbleRun::Store have to be used.

=head1 METHODS

Whenever in the methods arguments for describing a position are used, they
are typically called $x and $y or similar. Please note that $x means the
row number, $y the column number, i.e. $x=1, $y=2 is the position to the
right of the left upper edge of the board. The x and y positions are
positive integer numbers. Denoting the position using also letters as in
the notation of a marble run cannot be used.

=head2 new (constructor)

$g = Game::MarbleRun->new(%attr);

Creates a new game object and initializes a sqlite database if not yet
existing. By default the DB is located at ~/.gravi.db in the callers home
directory. The DB is populated initially with information on GraviTrax®
construction sets and elements. Sets the viewport and creates a white
background. The following attrs can be used:

  verbose     => 1               sets verbosity
  db          => "<file name>"   alternate name andplace of the DB
  screen_x    => <screen x size in pixels> (default 800)
  screen_y    => <screen y size in pixels> (default 600)

=head2 orientations

$g->orientations($case);

An svg image is generated that shows the different orientations of tiles.
If case is not given, an image for basic tiles orientations is generated.
The cases 'balcony', 'extra curves' and 'all' produce similar images.
The resulting image for case 'all' is contained in gravi_en.pdf.

=head2 board

$g->board($size_x, $size_y, $run_id, $fill);

generates the svg code for drawing a board with size_x columns * size_y rows.
If size_x and size_y are not given the board size is calculated from the
data of the marble run whose run_id is given. Write the board positions
on the board, if fill is set. Otherwise a frame with position numbers
around the board is printed.

=head2 draw_tile

$g->draw_tile($element, $x, $y, $orientation, $detail);

generates the svg code for placing a tile at position x, y. The element is the
symbol code of the tile.

=head2 draw_rail

$g->draw_rail($element, $x1, $y1, $x2, $y2, $dir);

generates the svg code for placing a rail from position x1, y1, to x2, y2. The
element is the symbol code of the rail. The direction is a number 0..5.

=head2 put_Balls

$g->put_Balls($x, $y, $offset, $marble, $t0, $t_dur, $path);

Place balls at tile given by x and y. The marbles are by an offset away
from the center of the tile, if given. The marble information is an arrayref
with triples [$id, $orient, $color] for each marble to be drawn. The offset
is either a scalar valid for all marbles or an arrayref with tuples
[$rel_x_off, $rel_y_off] for each marble defined.
The balls get animated along $path starting at time t0 and lasting for t_dur
seconds.

=head2 do_run

$g->do_run($run_id);

Starting from The Lifter or Start tile the paths of the marbles are checked
(method neighbor with rule definitions in features and checks in rule check)
and the path of the marbles is calculated (generate_path).
Finally the marbles are animated along the calculated path and marbles that
did not move are drawn. Most part of the method is not yet functional.

=head2 emit_svg

$g->emit_svg($name, $level);

Produces a name.svg file from the generated svg code. If level is given,
intermediate files name_$level.svg where only elements up to the given
level are drawn. If no name is given, it will be queried.
The svg code can be obtained also by directly calling xmlify
(and then be printed etc.) from svg as follows:

$g->{svg}->xmlify();

=head2 DRAWING INDIVIDUAL TILES

instead of using the draw_tile method and giving an element character to
generate code for placing tiles some individual methods can be used instead.
For example the svg code for a magnetic cannon tile can be generated by

$g->draw_tile('M', $x, $y, $orient); or equivalently by

$g->put_Cannon($x, $y, $orient);

Where no specific method exists, the method put_Tile is called instead.

The following individual methods are currently defined

  $g->put_Tile($x, $y, $element, $orient, $detail);
  $g->put_TransparentPlane($x, $y, $type);
  $g->put_1($x, $y, $elem_char);
  $g->put_Cannon($x, $y, $orient);
  $g->put_FinishLine($x, $y, $orient);
  $g->put_OpenBasket($x, $y);
  $g->put_Balcony($x, $y, $orient);
  $g->put_DoubleBalcony($x, $y, $orient);
  $g->put_BridgetTile($x, $y, $orient, $detail);
  $g->put_Catapult($x, $y, $orient);
  $g->put_Lift($x, $y, $orient, $detail);
  $g->put_Spiral($x, $y, $orient, $detail);
  $g->put_TipTube($x, $y, $orient);
  $g->put_BasicTile($x, $y, $orient);
  $g->put_Start($x, $y, $orient);
  $g->put_Landing($x, $y, $orient);
  $g->put_Drop($x, $y, $orient);
  $g->put_Catcher($x, $y, $orient);
  $g->put_Volcano($x, $y, $orient);
  $g->put_Splash($x, $y, $orient);

=head1 HELPER METHODS

=head2 svg_defs

$g->svg_defs();

creates the defs section in the svg and defines gradient and style information.
Called from new.

=head2 gradient

gradient($defs, $name, $fromcol, $tocol);

adds linear gradients to the svg defs. Gets called from svg_defs.

=head2 set_size

$g->set_size($pixels);

sets the vertical size of tiles. The size is calculated from the viewport and
board dimensions, set_size is called in the board method.

=head2 center_pos

($x_svg, $y_svg) = $g->center_pos($x, $y);

calculates the coordinates of a tile at position x,y in the svg coordinate
system (pixel based)

=head2 put_hexagon

$g->put_hexagon($x, $y, $rel_size, $style, $shape, $orient);

generates the svg code for drawing a hexagon with rel_size at the position
x,y. For shape=1 a balcony, for shape=2 a double balcony is drawn. Only
for shape=2 the orientation is needed. The size of the hexagon is defined
by the fraction rel_size of the tile height.
Style definitions can be given and will be added to the default style.
The total height of the hexagon is defined by the method set_size.

=head2 put_hexagon2

$g->put_hexagon2($x, $y, $rel_size, $style, $shape);

generates the svg code for drawing a full hexagon (shape 0), the upper half
(shape 1) or the lower half (shape 2) at the position x,y. Style definitions
and a relative size can be given. For rel_size = 1 the height of the hexagon
is equal to size, which is defined by the method set_size. The defaults are
shape 0, style: fill with white, rel_size 1.

=head2 put_arc

$g->put_arc($x, $y, $size, $orientation);

generates the svg code for drawing the bigger (size=2) / smaller (size=1)
arc in a curve tile.

=head2 put_circle

$g->put_circle($x, $y, $r, $style);

generates the svg code for drawing a circle with radius r (in pixels).

=head2 put_through_line

$g->put_through_line($x, $y, $orientation, $fraction);

generates the svg code for drawing a line through a hexagon with center x, y.
A fraction of the full size of a hexagon can be specified to draw shorter lines.

=head2 put_text

$g->put_text($x, $y, $text, $attributes);

generates the svg code for placing text at x, y. The calculated font-size can
be deleted with {'font-size'=>''} or be overridden in the hashref attributes.
The text is centered around x,y.

=head2 put_lever

$g->put_lever($x, $y, $orient, $detail);

draw the lever of a switch tile. If the detail is given (+ or -) the lever is
rotated clockwise or anticlockwise.

=head2 put_middleBar

$g->put_middleBar($x, $y, $orient, $offset, $length);

draw a bar in the middle of a tile with thickness 2*offset and the given
length perpendicular to the direction $orient.

=head2 put_arc_or_bezier

$g->arc_or_bezier($x, $y, $dir, $offset, $length, $r, $closed, $bezier);

Draw an arc or a bezier curve, if $bezier is true. The curve is closed if
the corresponding flag is set. The distance between the start and end
points of the curve is length, its distance from ce center is given by
offset. The curvature is given by $r (also for the bezier curve).

=head1 SEE ALSO

See also the documentation in Game::MarbleRun and Game::MarbleRun::Store.
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

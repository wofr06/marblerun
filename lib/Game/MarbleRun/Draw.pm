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

sub new {
	my ($class, %attr) = @_;
	my $self = {
		verbose => $attr{verbose} || 0,
		screen_x => $attr{screen_x} || 800,
		screen_y => $attr{screen_y} || 600,
		# text adjust in svg if dominant-baseline not understood
		text_offset => $attr{text_offset} ? 1 : 0,
		db => $attr{db} || $Game::MarbleRun::DB_FILE,
	};
	bless $self => $class;
	# set viewport workaround for: style => {'viewport-fill' => 'white'}
	my $svg = SVG->new(width => $self->{screen_x}, height => $self->{screen_y});
	$svg->rect(width=>"100%", height=>"100%", fill=>"white");
	$self->{svg} = $svg;
	# defs section in svg
	$self->svg_defs();
	# db initialization and preloading of frequently used data
	$self->config();
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
	my $start = 2;
	my $shift = 6;
	my $elems = { '0.5' => 'Orientation', 2 => 'C', 4 => 'Y,S', 6 => 'X',
		8 => 'G,D', 10 => 'Straight Tile', 12 => 'xG', 14 => 'B'};
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
		$start = 7;
		$shift = 15;
		$elems = { '0.5' => 'Orientation', 2 => 'C', 4 => 'Y,S', 6 => 'X',
        8 => 'G,D', 10 => 'Straight Tile', 12 => 'xG', 14 => 'B', 16 => 'xC',
		18 => 'yC', 20 => 'xW', 22 => 'yW', 24 => 'xY', 26 => 'yY', 28 => 'xX',
		30 => 'yX', 32 => 'xI', 34 => 'yI', 36 => 'xQ', 38 => 'xV,yV'};
	}
	my %label;
	my $size_y= 0;
	for my $k (keys %$elems) {
		if (length $elems->{$k} < 3 or $elems->{$k} =~ /,/) {
			my @e = split /,/, $elems->{$k};
			$label{$k} = join ', ', map {loc $self->{elem_name}{$_}} @e;
			$elems->{$k} = $e[0];
		} else {
			$label{$k} = loc($elems->{$k});
		}
		$size_y = $k if $k > $size_y;
	}
	$size_y = 20 if $size_y < 20;
	$self->set_size(int $self->{screen_y}/($size_y + 2));
	$elems->{'0.5'} = 'Symbol';
	$self->put_text($start - 4, $_, $elems->{$_}) for sort keys %label;
	$self->put_text($start, $_, $label{$_}) for sort keys %label;
	delete $elems->{'0.5'};
	for my $orient (0..5) {
		my $x = 2*$orient + $shift;
		$self->put_text($x, 0.5, chr($orient+97));
		$self->draw_tile($elems->{$_}, $x, $_, $orient) for sort keys %$elems;
	}
}

sub board {
	my ($self, $board_y, $board_x, $run_id, $fill_coord, $excl) = @_;
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
	my $size = int min($screen_x/(6*$board_x + 1), $screen_y/(5*$board_y + 2));
	$self->set_size($size);
	# write the coordinate labels
	for my $x (1..6*$board_x) {
		my $y = $x % 2 ? 0 : -0.5;
		my $xx = $self->{relative} ? (($x - 1) % 6) + 1 : $x;
		my $chr = $xx < 10 ? "$xx" : chr($x+87);
		$self->put_text($x, $y, $chr) if ! $fill_coord;
	}
	for my $y (1..5*$board_y) {
		my $yy = $self->{relative} ? (($y - 1) % 5) + 1 : $y;
		my $chr = $yy < 10 ? "$yy" : chr($y+87);
		if (! $fill_coord) {
			$self->put_text(0, $y, $chr);
			$self->put_text(6*$board_x+1, $y, $chr);
		}
	}
	# draw the board
	my $scale = [1., 14./15., 0.5];
	my $fill = ['url(#gray_yminus)', 'url(#gray_yplus)', 'white'];
	my $fill2 = ['url(#green_yminus)', 'url(#green_yplus)', 'white'];
	for my $lay (0, 1, 2) {
		for my $x (1..6*$board_x) {
			for my $y (0..5*$board_y) {
				my $shape = 0;
				my $s = {fill => $fill->[$lay]};
				if ($x % 2) {
				next if $y == 0;
					$s = {fill => $fill2->[$lay]} if $y % 5 == 1;
				} else {
					$s = {fill => $fill2->[$lay]} if $y % 5 == 3;
					$shape = 1 if $y == 0;
					$shape = 2 if $y == 5*$board_y;
				}
				$s->{stroke} = 'none';
				$self->put_hexagon2($x, $y, $scale->[$lay], $s, $shape);
				my $pos = $self->num2pos($x, $y, 1);
				$pos =~ s/.* (?!11)//;
				$self->put_text($x, $y, $pos) if $fill_coord and ! $shape;
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
		my $points = $svg->get_path(x => [$x0, $x0, $x1, $x1],
			y => [$y0, $y1, $y1, $y0], -closed => 1, -type => 'polygon');
		$svg->polygon(%$points, style => {fill => 'white', stroke =>'none'},
			class =>'tile');
	}
	return 1;
}

sub draw_tile {
	my ($self, $elem, $x, $y, $orient, $detail) = @_;
	return if ! $self->{svg};
	if ($elem eq 'A') {
		$self->put_Start($x, $y, $orient);
	} elsif ($elem eq 'Z') {
		$self->put_Landing($x, $y, $orient);
	} elsif ($elem eq 'xS') {
		$self->put_Spinner($x, $y);
	} elsif ($elem eq 'M') {
		$self->put_Cannon($x, $y, $orient);
	} elsif (($_) = grep {$elem eq $_} qw(xA xZ H J K M Q)) {
		$self->put_hexagon($x, $y);
		$self->put_through_line($x, $y, $orient, 0.3);
		$self->put_through_line($x, $y, $orient + 3, 0.3);
		$self->put_text($x, $y, $_);
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
	} elsif ($elem eq 'E') {
		$self->put_DoubleBalcony($x, $y, $orient);
	} elsif ($elem eq 'B') {
		$self->put_Balcony($x, $y, $orient);
	} elsif ($elem eq '^' or $elem eq '=') {
		$self->put_TransparentPlane($x, $y, $elem);
	# height tiles
	} elsif (($_) = grep {$elem eq $_} qw(1 + L xL)) {
		$self->put_1($x, $y, $elem);
	# special cases for generic elements
	} elsif ($elem eq 'xG') {
		$self->put_BasicTile($x, $y, $orient);
	# other tiles (F,R,xD,xM,xR,xS,xV) handled here (hexagon plus symbol)
	} else {
		$self->put_Tile($x, $y, $elem, $orient, $detail);
	}
}

sub put_Tile {
	my ($self, $x, $y, $elem, $orient_in, $detail) = @_;
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
			$self->put_circle($x, $y, $r, $style);
		} elsif ($type eq 'I') {
			my $frac = $thickness if grep {$elem eq $_} qw(V xV);
			$self->put_through_line($x, $y, $orient, $frac);
		} elsif ($type eq 'S') {
			my $scale = $self->{twoby3} if $elem eq 'U';
			$self->put_lever($x, $y, $orient, $detail, $scale);
		} elsif ($type eq 'T') {
			$self->put_text($x, $y, $elem);
		} elsif ($type eq 'H') {
			$self->put_hexagon($x, $y, $self->{twoby3}, {fill=>'url(#mygreen)',
				'fill-opacity' => '0.8',});
		}
	}
}

sub draw_rail {
	my ($self, $elem, $posx1, $posy1, $posx2, $posy2, $dir, $detail) = @_;
	my $svg = $self->{svg};
	return if ! $svg;
	my $style = {'stroke-width' => $self->{small_width}};
	# curved bernoulli rails
	if ($elem =~ /^[cd]$/) {
		my $inc = $elem eq 'c' ? -1 : 1;
		my ($xc, $yc) = $self->to_position($posx1, $posy1, $dir + 3 + $inc, 1);
		$self->put_arc($xc, $yc, 2, $dir - $inc - 2);
		return;
	} elsif ($elem eq 'e') {
		$self->put_FinishLine($posx1, $posy1, $dir);
		return;
	# flextube
	} elsif ($elem eq 'xt') {
		my ($xc, $yc) = $self->to_position($posx1, $posy1, $detail + 3, 1);
		my ($x1, $y1) = $self->center_pos($posx1, $posy1);
		my $dx1 = $self->{middle_x}[$detail];
		my $dy1 = $self->{middle_y}[$detail];
		my ($x12, $y12) = $self->center_pos($xc, $yc);
		my $dx2 = $self->{middle_x}[$dir];
		my $dy2 = $self->{middle_y}[$dir];
		my ($x2, $y2) = $self->center_pos($posx2, $posy2);
		$svg->line(x1 => int($x1 - $dx1), y1 => int($y1 - $dy1), x2 => int $x12,
			y2 => int $y12, style => $style, class=>'tile');
		$svg->line(x1 => int $x12, y1 => int $y12, x2 => int($x2 + $dx2),
			y2 => int($y2 + $dy2), style => $style, class=>'tile');
		return;
	}
	# straight rails
	my ($x1, $y1) = $self->center_pos($posx1, $posy1);
	my $dx = $self->{middle_x}[$dir];
	my $dy = $self->{middle_y}[$dir];
	my ($x2, $y2) = $self->center_pos($posx2, $posy2);
	($style->{stroke}, $style->{fill}) = qw(lightblue lightblue)
		if $elem =~ /x[sml]/;
	# vertical rail
	if ($elem eq 't') {
		$x1 = $x1 + 2.5*$dx;
		$y1 = $y1 + 2.5*$dy;
	}
	$svg->line(x1 => int($x1 - $dx), y1 => int($y1 - $dy), x2 => int($x2 + $dx),
		y2 => int($y2 + $dy), style => $style, class=>'tile');
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
		my $dy3 = $self->{size}*(1 - $rel_size);
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
		%rot = (transform => "rotate($angle, $x, $y)");
	}
	$hex =~ s/\.\d+ / /g;
	$self->{svg}->path(d => $hex, %rot, style => $style, class =>'tile');
	if ($shape == 1) {
		$mx = $x + 1.5*$self->{width3};
		$my = $y - 1.5*$self->{small_width};
		my $dlx = 0.37*$self->{size};
		my $dlx2 = $self->{small_width};
		my $dly = 3*$dlx2;
		my $dly2 = 0.5*$dly;
		my $clip = "M$mx $my l0 $dly l-$dlx 0 l-$dlx2 -$dly2 l$dlx2 -$dly2 Z";
		$clip =~ s/\.\d+ / /g;
		$self->{svg}->path(d => $clip,
			style => {stroke => 'url(#mygreen)', fill => 'url(#mygreen)'},
			%rot, class =>'tile');
	}
}

sub put_hexagon2 {
	my ($self, $posx, $posy, $rel_size, $style_in, $shape) = @_;
	my $svg = $self->{svg};
	my $style = {};
	if ($style_in) {
		$style->{$_} = $style_in->{$_} for keys %$style_in;
	}
	$shape = 0 if ! $shape or $shape > 2;
	# 0=full hex, 1=upper half, 2=lower half
	my ($xh, $yh);
	my ($x, $y) = $self->center_pos($posx, $posy);
	@$xh = map {int($x + $rel_size*$_)} @{$self->{corner_x}->[$shape]};
	@$yh = map {int($y + $rel_size*$_)} @{$self->{corner_y}->[$shape]};

	my $points = $svg->get_path(x => $xh, y => $yh,
		-closed => 1, -type => 'polygon');
	$svg->polygon(%$points, style => $style, class =>'tile');

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
	$x1 = int($x + $self->{middle_x}[($orient) % 6]);
	$y1 = int($y + $self->{middle_y}[($orient) % 6]);
	$x2 = int($x + $self->{middle_x}[($size+$orient) % 6]);
	$y2 = int($y + $self->{middle_y}[($size+$orient) % 6]);
	$svg->path(d => "M $x1 $y1 A $r $r 0 0 0 $x2 $y2", class => 'tile');
}

sub put_circle {
	my ($self, $posx, $posy, $r, $style_in) = @_;
	my $svg = $self->{svg};
	my ($x, $y) = $self->center_pos($posx, $posy);
	my $style = {stroke=>'black', fill=>'none'};
	if ($style_in) {
		$style->{$_} = $style_in->{$_} for keys %$style_in;
	}
	$svg->circle(cx=>int $x, cy=>int $y, r=>$r*$self->{size}, style=>$style);
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
	$svg->line(x1=>int $x1, y1=>int $y1, x2=>int $x2, y2=>int $y2, class=>'tile');
	return ($x2, $y2);
}

sub put_text {
	my ($self, $posx, $posy, $text, $attrib_in) = @_;
	my ($x, $y) = $self->center_pos($posx, $posy);
	# adjust the text in pngs (dominant-baseline not understood)
	my $svg = $self->{svg};
	my $rel_size = min($self->{screen_x}, $self->{screen_y})/600;
	my $font_size = 16/600*min($self->{screen_x}, $self->{screen_y});
	$y += 6*$rel_size if $self->{text_offset};
	my $attrib = {
		'font-family' => 'Arial',
		'font-size' => 12*$rel_size,
		'text-anchor'=> 'middle',
		'dominant-baseline' => 'central'
	};
	if ($attrib_in) {
		$attrib->{$_} = $attrib_in->{$_} for keys %$attrib_in;
	}
	$svg->text(x => int $x, y => int $y, %$attrib)->cdata_noxmlesc($text);
}

sub put_TransparentPlane {
	my ($self, $posx, $posy, $elem) = @_;
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
	my $smallhex = "l$ldx,0 l$ldx2,$ldy l-$ldx2,$ldy l-$ldx,0 l-$ldx2,-$ldy Z";
	my $holes;
	if ($elem eq '^') {
		for my $x (-2 .. 2) {
			for my $y (0 .. 4) {
				my $mx = $m1x + $x*$off_x;
				my $my = $m1y - 2*$y*$dy + (abs($x) == 1 ? $dy : 0);
				next if abs($x) >= 1 and ! $y or abs($x) == 2 and $y == 4;
				$holes .= " M$mx,$my $smallhex";
			}
		}
	} else {
		for my $x (-1 .. 1) {
			for my $y (0 .. 2) {
				my $mx = $m1x + $x*$off_x;
				my $my = $m1y - 2*$y*$dy + (abs($x) == 1 ? $dy : 0);
				next if $x and ! abs($y);
				$holes .= " M$mx,$my $smallhex";
			}
		}
	}
	my $plane = "l$dx,0 l$dx2,-$dy " x $num;
	$plane .= "l-$dx2,-$dy l$dx2,-$dy " x ($num - 1);
	$plane .= "l-$dx2,-$dy l-$dx,0 " x $num;
	$plane .= "l-$dx2,$dy l-$dx,0 " x ($num - 1);
	$plane .= "l-$dx2,$dy l$dx2,$dy " x $num;
	$plane .= "l$dx,0 l$dx2,$dy " x ($num - 1);
	$plane =~ s/\.\d+([, ])/$1/g;
	$holes =~ s/\.\d+([, ])/$1/g;
	my $style = {stroke=>'lightblue', fill=>'lightblue', opacity=>'0.5'};
	$svg->path(d=>"M $m0x,$m0y $plane Z$holes", style => $style);
}

sub put_1 {
	my ($self, $x, $y, $elem) = @_;
	my $color = $elem eq '+' ? 'black' : 'gray';
	$self->put_hexagon($x, $y, .76, {fill => $color});
	$self->put_hexagon($x, $y, .5, {fill => 'url(#mygreen)'}) if $elem =~ /L/;
}

sub put_lever {
	my ($self, $posx, $posy, $orient, $detail, $scale) = @_;
	my $svg = $self->{svg};
	$scale ||= 1.;
	my ($xc, $yc) = $self->to_position($posx, $posy, 0, 0.3*$scale);
	my ($x, $y) = $self->center_pos($xc, $yc);
	my %c = (q => 50, lg => 45, r => 22.5, ly => 375, lx => 10);
	$_ *= $self->{size}/600.*$scale for values %c; # scale coordinates
	my $q2 = 2*$c{q};
	my $q4 = 2*$q2;
	my $lg2 = 2*$c{lg};
	my $l0x = $x - $lg2 - $q2;
	my $l0y = $y - sqrt(0.8*$c{r}**2);
	my $l1y = $y + sqrt(0.8*$c{r}**2);
	my $l2x = $x + $q2 + $lg2;
	my $dx_bez = $q2 + $lg2 - 0.5*$c{lx};
	my $dy_bez = $c{ly} - $c{q};
	my $angle = 60 * (($orient + 3) % 6);
	$detail = $detail ? ($detail eq '+' ? 15 : -15) : 0;
	my ($xm, $ym) = $self->center_pos($posx, $posy);
	my $g = $svg->group(id => "lever$posx$posy", style => {fill => 'url(#mygreen)'},
		transform => "rotate($angle, $xm, $ym)");
	$g->path(d =>"M $l0x $l1y A $c{r} $c{r} 0 0 1 $l0x $l0y l $lg2 -$c{lg}
		q $q2 -$c{q} $q4 0 l $lg2 $c{lg} A $c{r} $c{r} 0 0 1 $l2x $l1y
		c -$dx_bez $c{q} -$dx_bez $yc -$dx_bez $c{ly} l -$c{lx} 0
		c 0 -$c{ly} -$q2 -$dy_bez -$dx_bez -$c{ly}",
		transform => "rotate($detail, $xm, $l1y)");
}

sub put_Looptile {
	my ($self, $posx, $posy, $orient) = @_;
	my $svg = $self->{svg};
	$self->put_hexagon($posx, $posy);
	my ($x, $y) = $self->center_pos($posx, $posy);
	my $angle = $orient*6.2832/6.;
	my $dy0 = 0.1;
	my $dx0 = -$dy0/sqrt(3);
	my $r = 1./3.*$self->{size};
	my $style = {fill => 'none', stroke=>'black'};
	my $dx = $self->{size}*(cos($angle)*$dx0 - sin($angle)*$dy0);
	my $dy = $self->{size}*(sin($angle)*$dx0 + cos($angle)*$dy0);
	$svg->circle(cx => $x + $dx, cy => $y +$dy, r => $r, style => $style);
	$self->put_through_line($posx, $posy, $orient, 0.275);
	$self->put_through_line($posx, $posy, $orient + 1, 0.275);
}

sub put_Cannon {
	my ($self, $x, $y, $orient) = @_;
	$self->put_hexagon($x, $y);
	$self->put_hexagon($x, $y, 0.6, {fill => 'url(#mygreen)'});
	$self->put_through_line($x, $y, $orient, 0.2);
	$self->put_through_line($x, $y, $orient + 3, 0.2);
	my $length = 0.8;
	$self->put_middleBar($x, $y, $orient, $self->{r_ball}, $length);
}

sub put_middleBar {
	my ($self, $x, $y, $dir, $offset, $length) = @_;
	my $svg = $self->{svg};
	my $d2 = ($dir + 2) % 6;
	my ($x1, $y1) = $self->center_pos($x, $y);
	my ($dx, $dy) = ($length*$self->{corner_x}[0][$d2],
		$length*$self->{corner_y}[0][$d2]);
	$svg->line(x1 => $x1-$dx, y1 => $y1-$dy, x2 => $x1+$dx, y2 => $y1+$dy,
		class => 'tile', style=>{'stroke-width' => 2*$offset*$self->{size},
		stroke =>'white'});
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
		$svg->path(d => "M $x1 $y1 Q $dq1 $dq2 $x2 $y2 $z", class => 'tile');
	} else {
		$r *= $self->{size};
		$svg->path(d => "M $x1 $y1 A $r $r 0 0 0 $x2 $y2 $z", class => 'tile');
	}
}

sub put_Balls {
	my ($self, $xm, $ym, $offset, $marble, $begin, $dur, $path) = @_;
	# balls are displayed in its initial state for 1s then the animation starts
	$path ||= 'M 0 0';
	my %srgb = (S=>'#d5d5d5', R=>'#d54545', G=>'#45d545', B=>'#45d5d5',
		A=>'#ffd700');
	my $svg = $self->{svg};
	my $cnt = 0;
	my $r = $self->{r_ball}*$self->{size};
	my ($x0, $y0) = $self->center_pos($xm, $ym);
	my $old_dir = 0;
	my $mcnt=0;
	for my $m (@$marble) {
		my $dir = $m->[1];
		my $id = "$xm$ym$dir$cnt";
		next if ! defined $dir;
		$id = "run$id$cnt" if $path;
		$cnt = 0 if $dir ne $old_dir;
		my $color = $m->[2] || 'S';
		my ($x, $y) = ($x0, $y0);
		if ($offset) {
			my ($x1, $y1) = $self->center_pos($self->to_position($xm,$ym,$dir,1));
			if (ref $offset) {
				next if ! @$offset;
				$cnt++;
				my ($offx, $offy) = @{shift @$offset};
				($x, $y) = ($x0+$offx*($x1-$x0)+$offy*($y1-$y0),
							$y0-$offy*($x1-$x0)+$offx*($y1-$y0));
			} else {
				my $frac = $offset + $self->{r_ball}*2*$cnt++;
				($x, $y) = ($x0+$frac*($x1-$x0), $y0+$frac*($y1-$y0));
			}
		}
		my $g = $svg->group(id => "marble$id");
		$g->circle(cx=>$x, cy=>$y, r=>$r, style=>{fill=>$srgb{$color}});
		my $tag = $g->gradient(-type => 'radial', id => "radial$id",
			gradientUnits => 'userSpaceOnUse', cx => $x, cy => $y, r => $r,
			fy => $y - 0.4*$r, fx => $x - 0.4*$r);
		$tag->stop(style=>{"stop-color"=>"#fff"});
		$tag->stop(style=>{"stop-color"=>"#fff"},"stop-opacity"=>0,offset=>.25);
		$tag->stop(style=>{"stop-color"=>"#000"},"stop-opacity"=>0,offset=>.25);
		$tag->stop(style=>{"stop-color"=>"#000"},"stop-opacity"=>0.7,offset=>1);
		$g->circle(cx=>$x,cy=>$y,r=>$r, style=>{fill=>"url(#radial$id)"});
		$g->animate('-method' =>'Motion', path=> $path, dur=>$dur,
			begin => $begin, fill=>'freeze') if $path;
		$old_dir = $dir;
	}
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

# the following two routines still need to be improved
sub put_BridgeTile {
	my ($self, $x, $y, $orient, $detail) = @_;
	my $thickness = (1 - $self->{twoby3})/2.;
	$self->put_hexagon($x, $y);
	$self->put_through_line($x, $y, $orient, 0.3);
	$self->put_through_line($x, $y, $orient + 3, 0.3);
	$self->put_text($x, $y, 'xB');
}

sub put_Catapult {
	my ($self, $x, $y, $orient) = @_;
	my $thickness = (1 - $self->{twoby3})/2.;
	$self->put_hexagon($x, $y);
	$self->put_through_line($x, $y, $orient, 0.3);
	$self->put_through_line($x, $y, $orient + 3, 0.3);
	$self->put_text($x, $y, 'xK');
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
	$cx += 2*$off_btn*$self->{corner_x}[0][($orient_out+5) % 6];
	$cy += 2*$off_btn*$self->{corner_y}[0][($orient_out+5) % 6];
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
	$svg->path(d => "M $x1 $y1 L $x2 $y2 A $r $r 0 0 1 $x3 $y3 A $r $r 0 0 1 $x5 $y5 L $x4 $y4", class => 'tile');
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
    $g->path(d => "M $x1 $y1 A $c{r} $c{r} 0 1 1 $x2 $y1 C $x0 $y3 $x4 $y4 $x4 $y4 L $x5, $y4 C $x5 $y5 $x0 $y3 $x1 $y1", transform => "rotate($detail, $x0, $y1)");
}

sub put_Spiral {
	my ($self, $x, $y, $orient, $elems) = @_;
	$elems ||= 0;
	my $thickness = 0.1;
	$self->put_hexagon($x, $y);
	$self->put_circle($x, $y, 0.5 - $thickness, {fill=>'url(#mygreen)'});
	$self->put_through_line($x, $y, $orient, $thickness);
	my $orient_in = $orient + 2*$elems - 1;
	$self->put_through_line($x, $y, $orient_in, $thickness);
	my ($xc, $yc) = $self->center_pos($x, $y);
	my $length = 0.4;
	my $d1 = ($orient_in + 4) % 6;
	my $d2 = ($orient_in + 5) % 6;
	my $d3 = ($orient_in) % 6;
	my $svg = $self->{svg};
	my $dx1 = $length*$self->{corner_x}[0][$d1];
	my $dy1 = $length*$self->{corner_y}[0][$d1];
	my $dx2 = $length*$self->{middle_x}[$d2];
	my $dy2 = $length*$self->{middle_y}[$d2];
	my $dx3 = $self->{middle_x}[$d3]*(1-2*$thickness);
	my $dy3 = $self->{middle_y}[$d3]*(1-2*$thickness);
	my ($x1, $y1) = ($xc - $dx1, $yc - $dy1);
	my ($x2, $y2) = ($xc + $dx2, $yc + $dy2);
	my ($x3, $y3) = ($xc + $dx3, $yc + $dy3);
	my $r = 0.21*$self->{size};
	my $r2 = 0.4*$self->{size};
	$svg->path(d => "M $x1 $y1 A $r $r 0 1 1 $x2 $y2", class => 'tile');
	$svg->path(d => "M $x2 $y2 A $r2 $r2 0 0 0 $x3 $y3", class => 'tile');
}

sub put_TipTube {
	my ($self, $x, $y, $orient) = @_;
	$self->put_hexagon($x, $y);
	# small curve
	$self->put_arc($x, $y, 1, $orient - 1);
	$self->put_text($x, $y, 't');
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
	my $thickness = (1 - $self->{twoby3})/2.;
	$self->put_hexagon($x, $y);
	$self->put_hexagon($x, $y, $self->{twoby3}, {fill=>'white'});
	$self->put_through_line($x, $y, $_, $thickness) for 0 .. 5;
	$self->put_circle($x, $y, 0.4, {fill => 'url(#mygreen)'});
	$self->put_circle($x, $y, 0.1, {fill => 'url(#mygreen)'});
}

sub put_Start {
	my ($self, $x, $y, $orient) = @_;
	$self->put_BasicTile($x, $y, $orient);
	$self->put_hexagon($x, $y, $self->{twoby3}, {fill => 'url(#mygreen)'});
	$self->put_circle($x, $y, 0.125);
	$self->put_circle($x, $y, 0.02, {fill => 'black'});
	my $sign = 1 - 2*($orient % 2);
	my ($cx, $cy) = $self->center_pos($x, $y);
	my $r = 7./60.*$self->{size};
	my ($x1, $y1) = ($cx - $sign*$r, $cy - $sign*0.3*$self->{size});
	my ($x2, $y2) = ($cx - $sign*$r, $cy - $sign*0.25*$self->{size});
	my ($x3, $y3) = ($cx + $sign*$r, $cy - $sign*0.25*$self->{size});
	my ($x4, $y4) = ($cx + $sign*$r, $cy - $sign*0.3*$self->{size});
	my %half_circle = (d => "M $x1 $y1 L $x2 $y2 A $r $r 0 0 0 $x3 $y3 L $x4 $y4", fill => 'white');
	$self->{svg}->path(%half_circle);
	$self->{svg}->path(%half_circle, transform => "rotate(120, $cx, $cy)");
	$self->{svg}->path(%half_circle, transform => "rotate(240, $cx, $cy)");
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
	my ($t_pos, $t_id, $state, $marble);
	my $i_tile = 0;
	my $ball = 0;
	# check if the code for animation is already working
	my $animate = not grep {/[FNOPRSUcdx]/} map {$_->[2]} @$tiles;
	# calculate positions of tiles and its states, get start tiles
	for my $t (@$tiles) {
		my ($sym, $x, $y, $z, $dir, $detail) = @{$t}[2 .. 7];
		# single action
		if (exists $self->{tile}{$sym} and $self->{tile}{$sym}[0][5] eq 's') {
			$state->{"$x,$y"}{$z} = 1;
		}
		# marbles
		if ($sym =~ /^[AMNP]|x[ABFKSTZ]/) {
			my $balls = [grep {$t->[0] == $_->[0]} @$marbles];
			if (!@$balls) {
				my $n=ref $self->{offset}{$sym} ? @{$self->{offset}{$sym}} : 1;
				push @$balls, [$t->[0], $dir, 'S'] for 1 .. $n;
			}
			$_->[1] = (defined $_->[1] ? $_->[1] : 'x') for @$balls;
			$_->[2] ||= 'S' for @$balls;
			$state->{"$x,$y"}{$z} .= "o$_->[2]$_->[1]" for @$balls;
			# start tile (no incoming direction, # of marbles times)
			# marble: tile_id z in out color
			#               0 1  2   3     4
			if ($sym eq 'A') {
				$marble->[$ball++] = [$i_tile, $z, '', @$_[1,2]] for @$balls;
			# lift can also be a start tile
			} elsif ($sym eq 'xF') {
				my $need = 3 + 4*(substr($detail, 0, 1) - 2);
				$marble->[$ball++] = [$i_tile, $z, '', $dir,
				@{$balls->[$need - 1]}[1,2]] if @$balls >= $need;
			}
		# switch
		} elsif ($sym =~ /^[SU]/) {
			$state->{"$x,$y"}{$z} = $detail;
		} elsif ($sym =~ /xM|yV/) {
			$state->{"$x,$y"}{$z} = 0;
		} elsif ($sym =~/[\d^+]/) {
			$i_tile++;
			next;
		}
		$t_id->{$t->[0]} = $i_tile;
		$t_pos->{"$x,$y"}{$z} = $i_tile++;
	}
# temporary check whether animation is already working
	if ($animate) {
	# begin is at start tile or lift
	my @colors = map {$_->[4]} @$marble;
	my $xyz = $self->neighbor($marble, $t_pos, $t_id, $tiles, $rails, $state);
	#print Dumper $xyz;exit;
	return if ! $xyz;
	my (@begin, @dur, @path, @p);
	my $i = 0;
	for my $p (@$xyz) {
		next if ! exists $p->[1];
		$p[$i] = $p;
		my ($sym, $x, $y) = @{$p->[0]}[0, 1, 2];
		($begin[$i], $dur[$i], $path[$i]) = $self->generate_path($i, $p);
		$i++;
	}
	$i = 0;
	# start fastest ball first
	my %dur = map {$i++, $_} sort {$a <=> $b} @dur;
	for my $k (sort {$a <=> $b} keys %dur) {
		my ($sym, $x, $y, $dir) = @{$p[$k][0]}[0, 1, 2, 5];
		$self->put_Balls($x, $y, $self->{offset}{$sym}, [[0, $dir, $colors[$k-1]]],
			$begin[$k], $dur[$k], $path[$k]);
	}
}
	# display the balls which have not moved
	for my $s (keys %$state) {
		for my $z (keys %{$state->{$s}}) {
			next if $state->{$s}{$z} !~ /o[RGBSA](\d|x)/;
			my @pos = grep {/^[RGBSA](\d|x)$/} split /o/, $state->{$s}{$z};
			#say "### @pos";
			my ($sym, $x, $y) = @{$tiles->[$t_pos->{$s}{$z}]}[2,3,4];
			my $desc = [map {[0, substr($_, 1, 1), substr($_, 0, 1)]} @pos];
			#print Dumper $desc;
			$self->put_Balls($x, $y, $self->{offset}{$sym}, $desc, 0, 1);
		}
	}
}

sub generate_path {
	my ($self, $ball, $xyz) = @_;
	my ($x0, $y0) = $self->center_pos($xyz->[0][1], $xyz->[0][2]);
	# start tile needs an offset in marble direction
	#print Dumper $xyz; exit;
	if ($xyz->[0][0] eq 'A') {
		my $dir = $xyz->[0][5];
		my ($dx, $dy) = (2*$self->{middle_x}[$dir], 2*$self->{middle_y}[$dir]);
		$x0 += 0.25*$dx;
		$y0 += 0.25*$dy;
	}
	my $path = "M 0 0";
	my $len = 0;
	for (my $i = 1; $i < @$xyz; $i++) {
		#print Dumper $xyz->[$i];
		my ($sym, $x, $y, $z, $dir) = @{$xyz->[$i]};
		last if ! $sym;
		if ($dir eq 'M') {
			my ($x,$y) = $self->center_pos($x, $y);
			$path .= " L " . ($x - $x0) . ' ' . ($y - $y0);
		} elsif ($dir eq '' or $dir < 0) {
			my ($x,$y) = $self->center_pos($x, $y);
			my $frac = 3*$self->{r_ball};
			# end of path finish line (e)
			if ($sym eq 'e') {
				$frac = 4*$self->{r_ball}*(($ball-1)%3);
			} else {
			# end of path landing (Z)
				$dir = (2*$ball + int($ball/3)) % 6;
			}
			my ($dx, $dy) = ($self->{middle_x}[$dir], $self->{middle_y}[$dir]);
			$path .= " L" . ($x - $x0 + $frac*$dx) . ' ' . ($y - $y0+ $frac*$dy);
		} elsif ($sym =~ /[a-w]/) {
			$len += $self->{rail}{$sym}[1];
			last if ! exists $xyz->[$i+1];
			my ($x,$y) = $self->center_pos($xyz->[$i+1][1], $xyz->[$i+1][2]);
			my ($dx, $dy) = ($self->{middle_x}[$dir], $self->{middle_y}[$dir]);
			$path .= " L " . ($x - $x0 - $dx) . ' ' . ($y - $y0 - $dy);
		} elsif ($sym =~ /^[CHIJKMQRTWXY]|x[BHKMRTV]/) {
			$len++;
			my ($x,$y) = $self->center_pos($x, $y);
			my $out = $xyz->[$i+1][4];
			$out = $xyz->[$i][5] if exists $xyz->[$i][5];
			#say "$sym in $dir out $out";
			$out = $dir if ! defined $out;
			my ($dx, $dy) = ($self->{middle_x}[$out], $self->{middle_y}[$out]);
			$x += $dx - $x0;
			$y += $dy - $y0;
			my $dir_diff = ($out - $dir) % 6;
			if ($dir_diff == 3) {
				$path .= " L $x $y";
			} else {
				my $r = (($dir_diff % 2) ? 0.5 : 1.5)*$self->{width3};
				my $flip = $dir_diff < 3 ? 0 : 1;
				$path .= "A $r $r 0 0 $flip $x $y";
			}
		} elsif ($sym eq 'V') {
			my ($xc,$yc) = $self->center_pos($x, $y);
			my $r = 0.2*$self->{size};
			my $turns= 2.5;
			$path .= spiral_path($xc - $x0, $yc -$y0, $r, $turns, $dir);
			$len += 2;
		}
	}
	$path =~ s/\.\d+ / /g;
	return (1, $len/4., $path);
}

sub spiral_path {
	my ($xm, $ym, $r, $turns, $dir) = @_;
	my ($old_th,$new_th, $old_r, $new_r, $old_p, $new_p, $old_slp, $new_slp);
	my $pi = 3.1416;
	my $th_step = 2*$pi*0.1;
	my $b = -$r/$turns/$pi/2;
	$old_th = $new_th = $pi*$dir/3;
	my $end_th = 2*$turns*$pi + $old_th;
	$old_r = $new_r = $r + $b*$new_th;
	$old_p = [0, 0];
	$new_p = [$xm + $new_r*cos($new_th), $ym + $new_r*sin($new_th)];
	$old_slp = $new_slp = ($b*sin($old_th) + ($r + $b*$new_th)*cos($old_th))/
		($b*cos($old_th) - ($r + $b*$new_th)*sin($old_th));
	my $path = " L$new_p->[0] $new_p->[1]";
	while ($old_th < $end_th - $th_step) {
		($old_th, $new_th) = ($new_th, $new_th + $th_step);
		($old_r, $new_r) = ($new_r, $r + $b*$new_th);
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

sub rule_check {
	my ($self, $ball, $tiles, $elem_in, $state, $xyz) = @_;
	my @dirs;
	my ($z_in, $dir_in, $dir_out) = @$elem_in[1..3];
	my $tile = $tiles->[$elem_in->[0]];
	#say "tile id ? sym x y z dir @$tile";

	my ($id, $sym, $x, $y, $z, $dir) = @$tile[0, 2..6];
	#say "$ball: In next tile $id $sym at xyz=$x,$y,$z, orient $dir ",
	#	"from z=$z_in dir $dir_in to dir $dir_out";
	for (@{$self->{tile}{$sym}}) {
		my ($r_in, $r_out, $r_zin, $r_zout, $r_cond) = @$_[1..$#$_];
		# drop, vortex, ...
		if ($r_out eq 'M') {
			@dirs = ('M') if ($z -$z_in) >= $r_cond;
			return @dirs;
		}
		#say "rule?$sym in=$r_in, out=$r_out z $r_zin -> $r_zout cond ",$r_cond||'';
		next if $r_in =~ /\d/ and $r_in != ($dir_in - $dir) % 6;
		#say "rule=$sym in=$r_in, out=$r_out z $r_zin -> $r_zout cond ",$r_cond||'';
		# marbles present
		if ($r_cond and $r_cond =~ /o(\d)/) {
			my $r_cond_out = ($1 + $dir) % 6;
			next if $r_cond_out ne $dir_out;
		print "dir_out=$1\n";
			if ($state->{"$x,$y"}{$z} =~ /($dir_out)|(x)/) {
				my $odir = defined $1 ? $1 : $2;
				print "dir_out ok\n";
				push @dirs, $dir_out;
				$state->{"$x,$y"}{$z} =~ s/$odir/-1/;
			}
		} else {
			# landing tile, finish track
			if ($r_out eq '') {
				push @{$xyz->[$ball]}, [$sym, $x,$y, $z, -1];
				undef $elem_in;
				last;
			}
			my $odir = ($dir + $r_out) % 6;
			#say "$sym: in $r_in out: $r_out, dir=$dir odir=$odir";
			push @dirs, $odir;
		}
	}
	#say "return @dirs";
	return @dirs;
}

sub neighbor {
	my ($self, $balls, $tile_pos, $tile_id, $tiles, $rails, $state) = @_;
	my ($xyz, @dirs);
	my $ball = 0;
	for my $m (@$balls) {
		$ball++;
		while ($m) {
			#say "ball $ball = id z dir in dir out col @$m";
			last if ! defined $m->[0];
			my ($z_elem, $dir_elem, $dir_out, $color) = @$m[1..4];
			my $t = $tiles->[$m->[0]];
			@dirs = ();
			my ($id, $sym, $x, $y, $z, $dir) = @$t[0, 2..6];
			#say "$ball: In tile $id $sym at xyz=$x,$y,$z, orient $dir ball in dir=", $dir_elem || '';
			push @{$xyz->[$ball]}, [$sym, $x, $y, $z, $dir_elem];
			# check condition
			my @res = $self->rule_check($ball, $tiles, $m, $state, $xyz);
			#say "out dirs = @res";
			$m = undef;
			for (@{$self->{tile}{$sym}}) {
				my ($elem, $in, $out, $z_in, $z_out, $cond) = @$_;
				# check incoming direction
				@dirs = ('M'), last if $out eq 'M';
				next if ! $in;
				next if $dir_elem =~/\d/ and ($dir_elem != ($in + $dir) % 6);
				# marbles present
				if ($cond and $cond =~ /o(\d)/) {
					my $odir = ($1 + $dir) % 6;
					next if $odir ne $dir_out;
					if ($state->{"$x,$y"}{$z} =~ /($odir)|(x)/) {
						$odir = defined $1 ? $1 : $2;
						# now no marble at this position
						push @dirs, $odir;
						$state->{"$x,$y"}{$z} =~ s/$odir/-/;
					}
				} else {
					# landing tile, finish track
					if ($out eq '') {
						undef $m;
						last;
					}
					my $odir = ($dir + $out) % 6;
					push @dirs, $odir if $dir_elem eq 'M' or $dir_elem != $odir;
				}
			}
			if (defined $dirs[0] and $dirs[0] eq 'M') {
				# look for tiles below current tile
				my $znew = $tile_pos->{"$x,$y"};
				$znew = (grep {$_ < $z} sort {$b <=> $a} keys %$znew)[0];
				my $tnew = $tile_pos->{"$x,$y"}{$znew};
				($id, $sym, $x, $y, $z, $dir) = @{$tiles->[$tnew]}[0, 2..6];
				$m = [$tile_pos->{"$x,$y"}{$z}, $z, 'M', $dir, $color];
				#say "$ball: $sym z=$z out=$dir, was ", $xyz->[$ball][-1][5] || -1;
				next;
			}
			#say "$ball: $sym dirs=@dirs";
			$xyz->[$ball][-1][5] = $dirs[0] if @dirs and @dirs == 1;

			for my $d (@dirs) {
				my ($x2, $y2) = $self->to_position($x, $y, $d, 1);
				my $xy = "$x2,$y2";
				if (exists $tile_pos->{$xy}) {
					# check z
					if (exists $tile_pos->{$xy}{$z_elem} or $z_elem < 0) {
						$z_elem = $z if $z_elem < 0;
						$m = [$tile_pos->{$xy}{$z_elem}, $z, ($d+3)%6, $d, $color];
						#say "$ball: $sym z=$z out=$d, was ", $xyz->[$ball][-1][5] || -1;
						$xyz->[$ball][-1][5] = $d;
						last;
					}
				}
				# check rails
				#print Dumper $rails;exit;
				for my $r (@$rails) {
					# outgoing dir for a rail is the from direction
					my ($t_id, $d_from);
					if ($r->[1] % 3 == $d % 3 and $r->[2] == $id) {
						$t_id = $tile_id->{$r->[4]};
					} elsif ($r->[1] % 3 == $d % 3 and $r->[4] == $id) {
						$t_id = $tile_id->{$r->[2]};
					} else {
						next;
					}
					#say "check rail $r->[0] on $id: conn at $r->[2],$r->[4], dir $r->[1]";
					# finish line, end of track
					if ($r->[0] eq 'e') {
						my ($x, $y) = $self->to_position($x, $y, $d, 1);
						push @{$xyz->[$ball]}, ['e', $x, $y, $z, -1];
						undef $m;
						last;
					}
					$d_from = ($d + 3) % 6;
					my $chk = $self->{rail}{$r->[0]};
					my $dz = abs($tiles->[$t_id][5] - $z);
					if ($dz < $chk->[2] or $dz > $chk->[3]) {
						say "$chk->[2] <= $dz <= $chk->[3] not true (should not happen)";
					}
					#say "$ball: $sym In rail $r->[0] dir $d z=$z -> $tiles->[$t_id][5] ";
					push @{$xyz->[$ball]}, [$r->[0],
						@{$tiles->[$t_id]}[3,4,5], $d];
					$m = [$t_id, -1, $d_from, $d, $color];
				}
			}
		}
	}
	#print Dumper $xyz;exit;
	return $xyz;
}

sub emit_svg {
	my ($self, $name, $level) = @_;
	my $svg = $self->{svg};
	return if ! $self->{svg};
	return if exists $self->{outputfile} and $self->{outputfile} =~ /^\s*$/;
	$name = $self->{outputfile} if exists $self->{outputfile};
	my $svgfile = $self->get_file_name($name, 'svg', loc("ENTER to exit"));
	$self->{outputfile} = $svgfile || '';
	return if ! $svgfile or $svgfile =~ /^\s*$/;
	if (defined $level and $level ne '') {
		($self->{outputfile} = $svgfile) =~ s/\.svg$//;
		$svgfile =~ s/\.svg$/_$level.svg/;
	} else {
		delete $self->{outputfile};
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
  $g = Game::MarbleRun::Draw->new(text_offset=>1);
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
  text_offset => 1 (shift in y direction if svg instruction
                    dominant-baseline is not respected)

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
with triples [$char, $orient, $color] for each marble to be drawn. The offset
is either a scalar valid for all marbles or an arrayref with tuples
[$rel_x_off, $rel_y_off] for each marble defined.
The balls get animated along $path starting at time t0 and lasting for t_dur
seconds.

=head2 do run

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

$g->put_text($x, $y, $text, $style);

generates the svg code for placing text at x, y. The default style (font
size etc.) can be overridden. The text is centered around x,y by setting the
dominant-baseline attribute. As this is not always respected, a pixel offset
can be added, if $g->{text_offset} is set.

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

$g->put_text($x, $y, $text, $style);

generates the svg code for placing text at x, y.

=head1 SEE ALSO

See also the documentation in Game::MarbleRun and Game::MarbleRun::Store.
The file gravi_en.pdf and gravi_de.pdf (in german) describe in more detail
the notation of marble runs.

=head1 AUTHOR

Wolfgang Friebel, E<lt>wp.friebel@gmail.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2020-2022 by Wolfgang Friebel

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.28.1 or,
at your option, any later version of Perl 5 you may have available.

=cut

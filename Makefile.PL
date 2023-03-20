use 5.028001;
use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME              => 'Game::MarbleRun',
    VERSION_FROM      => 'lib/Game/MarbleRun.pm',
    PREREQ_PM         => {
			'Getopt::Long'				=> 0,
			'DBD::SQLite'				=> 0,
			'Digest::MD5'				=> 0,
			'List::Util'				=> 0,
			'Locale::Maketext'			=> 0,
			'Locale::Maketext::Simple'	=> 0,
			'Locale::Maketext::Lexicon'	=> 0,
			'SVG'						=> 0,
			# for testing
			'Capture::Tiny'				=> 0,
			'Test::More'				=> 0,
	},
    ABSTRACT_FROM     => 'lib/Game/MarbleRun.pm',
	EXE_FILES         => [qw(
			script/gravi
			script/make_gravi_po_file
						)],
	dist              => {COMPRESS => 'gzip -f', SUFFIX => 'gz', },
    AUTHOR            => 'Wolfgang Friebel <wp.friebel@gmail.com>',
    LICENSE           => 'perl',
);

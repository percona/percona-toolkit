#!/usr/bin/perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More tests => 12;

use FileIterator;
use PerconaTest;

use constant PTDEBUG => $ENV{PTDEBUG} || 0;

use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

my $sample = "$trunk/t/lib/samples/";

my ($next_fh, $fh, $name, $size);
my $fi = new FileIterator();
isa_ok($fi, 'FileIterator');

# #############################################################################
# Empty list of filenames.
# #############################################################################
$next_fh = $fi->get_file_itr(qw());
is( ref $next_fh, 'CODE', 'get_file_itr() returns a subref' );
( $fh, $name, $size ) = $next_fh->();
is( "$fh", '*main::STDIN', 'Got STDIN for empty list' );
is( $name, undef, 'STDIN has no name' );
is( $size, undef, 'STDIN has no size' );

# #############################################################################
# Magical '-' filename.
# #############################################################################
$next_fh = $fi->get_file_itr(qw(-));
( $fh, $name, $size ) = $next_fh->();
is( "$fh", '*main::STDIN', 'Got STDIN for "-"' );

# #############################################################################
# Real filenames.
# #############################################################################
$next_fh = $fi->get_file_itr("$sample/slowlogs/slow002.txt", "$sample/empty");
( $fh, $name, $size ) = $next_fh->();
is( ref $fh, 'GLOB', 'Open filehandle' );
is( $name, "$sample/slowlogs/slow002.txt", "Got filename for $name");
is( $size, 3841, "Got size for $name");
( $fh, $name, $size ) = $next_fh->();
is( $name, "$sample/empty", "Got filename for $name");
is( $size, 0, "Got size for $name");
( $fh, $name, $size ) = $next_fh->();
is( $fh, undef, 'Ran off the end of the list' );

# #############################################################################
# Done.
# #############################################################################
exit;

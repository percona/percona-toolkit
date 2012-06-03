#!/usr/bin/perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More tests => 2;

use Outfile;
use DSNParser;
use Sandbox;
use PerconaTest;

# This is just for grabbing stuff from fetchrow_arrayref()
# instead of writing test rows by hand.
my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');

my $outfile = new Outfile();

sub test_outfile {
   my ( $rows, $expected_output ) = @_;
   my $tmp_file = '/tmp/Outfile-output.txt';
   open my $fh, '>', $tmp_file or die "Cannot open $tmp_file: $OS_ERROR";
   $outfile->write($fh, $rows);
   close $fh;
   my $retval = system("diff $tmp_file $expected_output");
   `rm -rf $tmp_file`;
   $retval = $retval >> 8;
   return !$retval;
}


ok(
   test_outfile(
      [
         [
          '1',
          'a',
          'some text',
          '3.14',
          '5.08',
          'Here\'s more complex text that has "quotes", and maybe a comma.',
          '2009-08-19 08:48:08',
          '2009-08-19 08:48:08'
         ],
         [
          '2',
          '',
          'the char and text are blank, the',
          undef,
          '5.09',
          '',
          '2009-08-19 08:49:17',
          '2009-08-19 08:49:17'
         ]
      ],
      "$trunk/t/lib/samples/outfile001.txt",
   ),
   'outfile001.txt'
);

# #############################################################################
# Done.
# #############################################################################
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;

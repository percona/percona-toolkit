#!/usr/bin/perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More;

use DSNParser;
use Sandbox;
use PerconaTest;
use OSCCaptureSync;

use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to MySQL';
  
}
else {
   plan tests => 4;
}

$sb->load_file("master", "t/lib/samples/osc/tbl001.sql");
$dbh->do("USE osc");

my $osc = new OSCCaptureSync();

my $msg = sub { print "$_[0]\n"; };

my $output = output(
   sub {
      $osc->capture(
         dbh          => $dbh,
         db           => 'osc',
         tbl          => 't',
         tmp_tbl      => '__new_t',
         columns      => [qw(id c)],
         chunk_column => 'id',
         msg          => $msg,
      )
   },
);

ok(
   no_diff(
      $output,
      "t/lib/samples/osc/capsync001.txt",
      cmd_output => 1,
   ),
   "SQL statments to create triggers"
);

$dbh->do('insert into t values (6, "f")');
$dbh->do('update t set c="z" where id=1');
$dbh->do('delete from t where id=3');

my $rows = $dbh->selectall_arrayref("select id, c from __new_t order by id");
is_deeply(
   $rows,
   [
      [1, 'z'],  # update t set c="z" where id=1
      [6, 'f'],  # insert into t values (6, "f")
   ],
   "Triggers work"
) or print Dumper($rows);

output(sub {
   $osc->cleanup(
      dbh => $dbh,
      db  => 'osc',
      msg => $msg,
   );
});

$rows = $dbh->selectall_arrayref("show triggers from `osc` like 't'");
is_deeply(
   $rows,
   [],
   "Cleanup removes the triggers"
);

# #############################################################################
# Done.
# #############################################################################
$output = '';
{
   local *STDERR;
   open STDERR, '>', \$output;
   $osc->_d('Complete test coverage');
}
like(
   $output,
   qr/Complete test coverage/,
   '_d() works'
);
$sb->wipe_clean($dbh);
exit;

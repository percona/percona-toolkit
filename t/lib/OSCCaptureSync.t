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
use Quoter;
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
   plan tests => 10;
}

my $q   = new Quoter(); 
my $osc = new OSCCaptureSync(Quoter => $q);
my $msg = sub { print "$_[0]\n"; };
my $output;

sub test_table {
   my (%args) = @_;
   my ($tbl, $col, $expect) = @args{qw(tbl col expect)};

   $sb->load_file("master", "t/lib/samples/osc/$tbl");
   PerconaTest::wait_for_table($dbh, "osc.t", "id=5");
   $dbh->do("USE osc");

   ok(
      no_diff(
         sub {
            $osc->capture(
               dbh          => $dbh,
               db           => 'osc',
               tbl          => 't',
               tmp_tbl      => '__new_t',
               columns      => ['id', $col],
               chunk_column => 'id',
               msg          => $msg,
            )
         },
         "t/lib/samples/osc/$expect",
         stderr => 1,
      ),
      "$tbl: SQL statments to create triggers"
   );

   $dbh->do("insert into t values (6, 'f')");
   $dbh->do("update t set `$col`='z' where id=1");
   $dbh->do("delete from t where id=3");

   my $rows = $dbh->selectall_arrayref("select id, `$col` from __new_t order by id");
   is_deeply(
      $rows,
      [
         [1, 'z'],  # update t set c="z" where id=1
         [6, 'f'],  # insert into t values (6, "f")
      ],
      "$tbl: Triggers work"
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
      "$tbl: Cleanup removes the triggers"
   );
}

test_table(
   tbl    => "tbl001.sql",
   col    => "c",
   expect => "capsync001.txt",
);

test_table(
   tbl    => "tbl002.sql",
   col    => "default",
   expect => "capsync002.txt",
);

test_table(
   tbl    => "tbl003.sql",
   col    => "space col",
   expect => "capsync003.txt",
);

# #############################################################################
# Done.
# #############################################################################
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

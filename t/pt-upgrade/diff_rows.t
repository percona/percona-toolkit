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

use PerconaTest;
use Sandbox;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

require "$trunk/bin/pt-upgrade";

my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');

if ( !$dbh ) {
   plan skip_all => "Cannot connect to sandbox master";
}

sub test_diff {
   my (%args) = @_;
   
   my $name   = $args{name};
   my $query1 = $args{query1};
   my $query2 = $args{query2};
   my $expect = $args{expect};

   my $sth1 = $dbh->prepare($query1);
   my $sth2 = $dbh->prepare($query2);

   $sth1->execute();
   $sth2->execute();

   my $diffs = pt_upgrade::diff_rows(
      sth1 => $sth1,
      sth2 => $sth2,
   );

   $sth1->finish();
   $sth2->finish();

   is_deeply(
      $diffs,
      $expect,
      $name,
   ) or diag(Dumper($diffs));
}

test_diff(
   name   => 'No diff',
   query1 => 'select user from mysql.user order by user',
   query2 => 'select user from mysql.user order by user',
   expect => [],
);

test_diff (
   name   => '2 diffs (ORDER BY ASC vs. DESC)',
   query1 => "select user from mysql.user order by user ASC",
   query2 => "select user from mysql.user order by user DESC",
   expect => [
      {
         row_number => 1,
         sth1_rows  => [qw(msandbox)],
         sth2_rows  => [qw(root)],
      },
      {
         row_number => 2,
         sth1_rows  => [qw(root)],
         sth2_rows  => [qw(msandbox)],
      }
   ],
);

test_diff (
   name   => "Stops when there's not 2 rows",
   query1 => "select user from mysql.user where user='msandbox' order by user",
   query2 => 'select user from mysql.user order by user',
   expect => [],
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;

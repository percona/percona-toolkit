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
use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

use Sandbox;
use PerconaTest;

require "$trunk/bin/pt-upgrade";

my $dp   = new DSNParser(opts=>$dsn_opts);
my $sb   = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh1 = $sb->get_dbh_for('master');
my $dbh2 = $sb->get_dbh_for('master');

if ( !$dbh1 || !$dbh2 ) {
   plan skip_all => "Cannot connect to sandbox master";
}

$sb->load_file('master', "t/lib/samples/compare-warnings.sql");

sub clear_warnings {
   $dbh1->do("SELECT /* clear warnings */ 1 FROM mysql.user");
   $dbh2->do("SELECT /* clear warnings */ 1 FROM mysql.user");
}

$dbh1->do("INSERT INTO test.t VALUES (2, '', 123456789)");
$dbh2->do("INSERT INTO test.t VALUES (3, '', 123456789)");

my $event_exec = EventExecutor->new();
my $w1 = $event_exec->get_warnings(dbh => $dbh1);
my $w2 = $event_exec->get_warnings(dbh => $dbh2);

my $error_1264 = {
   code    => '1264',
   level   => 'Warning',
   message => ($sandbox_version eq '5.0'
            ? "Out of range value adjusted for column 't' at row 1"
            : "Out of range value for column 't' at row 1"),
};

is_deeply(
   $w1,
   {
      1264 => $error_1264,
   },
   "host1 warning"
) or diag(Dumper($w1));

is_deeply(
   $w2,
   {
      1264 => $error_1264,
   },
   "... and host2 warning"
) or diag(Dumper($w2));

my $diffs = pt_upgrade::diff_warnings(
   warnings1 => $w1,
   warnings2 => $w2,
);

is_deeply(
   $diffs,
   [],
   '... but no diffs'
) or diag(Dumper($diffs));

$diffs = pt_upgrade::diff_warnings(
   warnings1 => {},
   warnings2 => $w2,
);

is_deeply(
   $diffs,
   [
      [
         1264,
         undef,
         $error_1264,
      ],
   ],
   "host1 doesn't have the warning"
) or diag(Dumper($diffs));

# #############################################################################
# Ignore warnings
# #############################################################################

$diffs = pt_upgrade::diff_warnings(
   ignore_warnings => { 1264 => 1 },
   warnings1       => $w1,
   warnings2       => $w2,
);

is_deeply(
   $diffs,
   [],
   'Ignore a warning'
) or diag(Dumper($diffs));

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh1);
diag(`$trunk/sandbox/stop-sandbox 12348 >/dev/null`);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;

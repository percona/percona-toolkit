#!/usr/bin/env perl

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
require "$trunk/bin/pt-archiver";

my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
else {
   plan tests => 8;
}

my $output;
my $sql;
my $cnf = "/tmp/12345/my.sandbox.cnf";
# Add path to samples to Perl's INC so the tool can find the module.
my $cmd = "perl -I $trunk/t/pt-archiver/samples $trunk/bin/pt-archiver";

# ###########################################################################
# Test the custom plugin res_fk.
# ###########################################################################
$sb->load_file('master', 't/pt-archiver/samples/res_fk.sql');
$sql = 'select * from test.comp';
is_deeply(
   $dbh->selectall_arrayref($sql),
   [
      [qw(1 Company1), 'best customer'],
      [qw(2 Company2), 'worst customer'],
      [qw(3 Company3), 'average joe'],
   ],
   'Have company2 before archive (res_fk plugin)'
);
is_deeply(
   $dbh->selectall_arrayref('select * from test_archived.comp'),
   [
   ],
   'No company2 archived yet (res_fk plugin)'
);

# MUST USE --txn-size 0
diag(`$cmd --where 'id=2' --source F=$cnf,D=test,t=comp,m=res_fk --dest D=test_archived,t=comp --txn-size 0`);

is_deeply(
   $dbh->selectall_arrayref($sql),
   [
      [qw(1 Company1), 'best customer'],
      [qw(3 Company3), 'average joe'],
   ],
   'company2 gone archive (res_fk plugin)'
);

# Make sure the archived tables have what they're supposed to.
is_deeply(
   $dbh->selectall_arrayref('select * from test_archived.comp'),
   [
      [qw(2 Company2), 'worst customer'],
   ],
   'test_archived.comp (res_fk plugin)'
);
is_deeply(
   $dbh->selectall_arrayref('select * from test_archived.user'),
   [
      [qw(3 2 3 gert-jan)],
   ],
   'test_archived.user (res_fk plugin)'
);
is_deeply(
   $dbh->selectall_arrayref('select * from test_archived.prod'),
   [
      [qw(3 2 lumber)],
      [qw(4 2 concrete)],
   ],
   'test_archived.prod (res_fk plugin)'
);
is_deeply(
   $dbh->selectall_arrayref('select * from test_archived.prod_details'),
   [
      [qw(3 3), 'totally different'],
      [qw(4 4), "I'm out of ideas"],
   ],
   'test_archived.prod_details (res_fk plugin)'
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;

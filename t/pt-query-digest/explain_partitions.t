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
use DSNParser;
use VersionParser;
use Sandbox;

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
elsif ( VersionParser->new($dbh) < '5.1' ) {
   plan skip_all => 'Sandbox master version not >= 5.1';
}
else {
   plan tests => 2;
}

# #############################################################################
# Issue 611: EXPLAIN PARTITIONS in mk-query-digest if partitions are used
# #############################################################################
diag(`/tmp/12345/use < $trunk/t/pt-query-digest/samples/issue_611.sql`);

my $output = `$trunk/bin/pt-query-digest $trunk/t/pt-query-digest/samples/slow-issue-611.txt --explain h=127.1,P=12345,u=msandbox,p=msandbox 2>&1`;
like(
   $output,
   qr/partitions: p\d/,
   'EXPLAIN /*!50100 PARTITIONS */ (issue 611)'
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;

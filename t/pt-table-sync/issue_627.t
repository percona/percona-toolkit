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
require "$trunk/bin/pt-table-sync";

my $output;
my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $source_dbh = $sb->get_dbh_for('source');
my $replica_dbh  = $sb->get_dbh_for('replica1');

if ( !$source_dbh ) {
   plan skip_all => 'Cannot connect to sandbox source';
}
elsif ( !$replica_dbh ) {
   plan skip_all => 'Cannot connect to sandbox replica';
}
else {
   plan tests => 2;
}

$sb->wipe_clean($source_dbh);
$sb->wipe_clean($replica_dbh);
$sb->create_dbs($source_dbh, [qw(test)]);

# #############################################################################
# Issue 627: Results for mk-table-sync --replicate may be incorrect
# #############################################################################
diag(`/tmp/12345/use < $trunk/t/pt-table-sync/samples/issue_375.sql`);
sleep 1;

# Make the table differ.
# (10, '2009-09-03 14:18:00', 'k'),    -> (10, '2009-09-03 14:18:00', 'z'),
# (100, '2009-09-06 15:01:23', 'cv');  -> (100, '2009-09-06 15:01:23', 'zz');
$replica_dbh->do('UPDATE issue_375.t SET foo="z" WHERE id=10');
$replica_dbh->do('UPDATE issue_375.t SET foo="zz" WHERE id=100');

# Checksum and replicate.
diag(`$trunk/bin/pt-table-checksum --create-replicate-table --replicate issue_375.checksum h=127.1,P=12345,u=msandbox,p=msandbox -d issue_375 -t t --set-vars innodb_lock_wait_timeout=3 > /dev/null`);

# And now sync using the replicated checksum results/differences.
$output = output(
   sub { pt_table_sync::main('--sync-to-source', 'h=127.1,P=12346,u=msandbox,p=msandbox', qw(--replicate issue_375.checksum --print)) },
   trf => \&remove_traces,
);
is(
   $output,
   "REPLACE INTO `issue_375`.`t`(`id`, `updated_at`, `foo`) VALUES ('10', '2009-09-03 14:18:00', 'k');
REPLACE INTO `issue_375`.`t`(`id`, `updated_at`, `foo`) VALUES ('100', '2009-09-06 15:01:23', 'cv');
",
   'Simple --replicate'
) or diag($output);

# Note how the columns are out of order (tbl order is: id, updated_at, foo).
# This is issue http://code.google.com/p/maatkit/issues/detail?id=371

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($source_dbh);
$sb->wipe_clean($replica_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;

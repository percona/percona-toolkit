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
require "$trunk/bin/pt-online-schema-change";
require VersionParser;

use Data::Dumper;

my $dp         = new DSNParser(opts=>$dsn_opts);
my $sb         = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $source_dbh = $sb->get_dbh_for('source');
my $replica_dbh  = $sb->get_dbh_for('replica1');

if ( !$source_dbh ) {
   plan skip_all => 'Cannot connect to sandbox source';
}
elsif ( !$replica_dbh ) {
   plan skip_all => 'Cannot connect to sandbox replica';
}

my @args   = qw(--set-vars innodb_lock_wait_timeout=3);
my $output = "";
my $dsn    = "h=127.1,P=12345,u=msandbox,p=msandbox";
my $exit   = 0;
my $sample = "t/pt-online-schema-change/samples";

$sb->load_file('source', "$sample/pt-2407.sql");

($output, $exit) = full_output(
   sub { pt_online_schema_change::main(@args, "$dsn,D=pt_2407,t=t1",
         '--alter', 'alter table t1 ADD COLUMN payout_group_id VARCHAR(255) DEFAULT NULL, ALGORITHM=INSTANT;', '--execute') }
);

is(
   $exit,
   11,
   'Return code non-zero for failed operation'
) or diag($exit);

like(
   $output,
   qr/You have an error in your SQL syntax/,
   'Job failed due to SQL syntax error'
) or diag($output);

like(
   $output,
   qr/Error altering new table/,
   'Error altering new table message printed'
) or diag($output);

# #############################################################################
# Done.
# #############################################################################

$sb->wipe_clean($source_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
#
done_testing;

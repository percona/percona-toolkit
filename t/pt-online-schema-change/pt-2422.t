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

$sb->load_file('source', "$sample/basic_no_fks_innodb.sql");
$source_dbh->do('CREATE TABLE pt_osc.pt_2422 LIKE pt_osc.t');
$source_dbh->do('INSERT INTO pt_osc.pt_2422 SELECT * FROM pt_osc.t');

($output, $exit) = full_output(
   sub { pt_online_schema_change::main(@args, "$dsn,D=pt_osc,t=t",
         '--alter', 'engine=innodb', '--execute', '--history') }
);

is(
   $exit,
   0,
   'basic test with option --history finished OK'
) or diag($output);

like(
   $output,
   qr/Job \d started/,
   'Job id printed in the beginning of the tool output'
);

like(
   $output,
   qr/Job \d finished successfully/,
   'Job id printed for successful copy'
);

$output = `/tmp/12345/use -N -e "SELECT new_table_name FROM percona.pt_osc_history WHERE job_id=1"`;

like(
   $output,
   qr/_t_new/,
   'Correct new table name inserted'
) or diag($output);

($output, $exit) = full_output(
   sub { pt_online_schema_change::main(@args, "$dsn,D=pt_osc,t=pt_2422",
         '--alter', 'engine=innodb', '--execute', '--history') }
);

is(
   $exit,
   0,
   'basic test with second table and option --history finished OK'
) or diag($output);

like(
   $output,
   qr/Job \d started/,
   'Job id printed in the beginning of the tool output for the second table'
);

like(
   $output,
   qr/Job \d finished successfully/,
   'Job id printed for successful copy of the second table'
);

$output = `/tmp/12345/use -N -e "SELECT new_table_name FROM percona.pt_osc_history WHERE job_id=1"`;

like(
   $output,
   qr/_t_new/,
   'New table name for previouse job was not updated'
) or diag($output);

$output = `/tmp/12345/use -N -e "SELECT new_table_name FROM percona.pt_osc_history WHERE job_id=2"`;

like(
   $output,
   qr/_pt_2422_new/,
   'Correct new table name inserted for the second table'
) or diag($output);

# #############################################################################
# Done.
# #############################################################################

$sb->wipe_clean($source_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
#
done_testing;

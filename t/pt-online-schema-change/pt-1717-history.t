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

($output, $exit) = full_output(
   sub { pt_online_schema_change::main(@args, "$dsn,D=pt_osc,t=t",
         '--alter', 'engine=innodb', '--execute') }
);

is(
   $exit,
   0,
   'basic test finished OK'
) or diag($output);

$output = `/tmp/12345/use -N -e "select count(*) from information_schema.tables where TABLE_SCHEMA='percona' and table_name='pt_osc_history'"`;

is(
   $output + 0,
   0,
   '--history table not created when option --history not provided'
);

unlike(
   $output,
   qr/Job \d started/,
   'Job id not printed in the beginning when option --history not provided'
);

unlike(
   $output,
   qr/Job \d finished successfully/,
   'Job id not printed in the end when option --history not provided'
);

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

$output = `/tmp/12345/use -N -e "select count(*) from information_schema.tables where TABLE_SCHEMA='percona' and table_name='pt_osc_history'"`;

is(
   $output + 0,
   1,
   '--history table created when option --history was provided'
);

$output = `/tmp/12345/use -N -e "select count(*) from percona.pt_osc_history where db='pt_osc' and tbl='t' and altr='engine=innodb' and json_extract(args, '\$.alter') = 'engine=innodb' and done='yes'"`;

is(
   $output + 0,
   1,
   'Initial row with Job ID was inserted into --history table'
);

$output = `/tmp/12345/use -N -e "select count(*) from percona.pt_osc_history where job_id=1 and lower_boundary is null and upper_boundary is null"`;

is(
   $output + 0,
   1,
   'Lower and upper boundaries were not updated when table altered with single chunk'
);

($output, $exit) = full_output(
   sub { pt_online_schema_change::main(@args, "$dsn,D=pt_osc,t=t",
         '--alter', 'engine=innodb', '--execute', '--history', '--chunk-size=4') }
);

$output = `/tmp/12345/use -N -e "select count(*) from percona.pt_osc_history where db='pt_osc' and tbl='t' and altr='engine=innodb' and json_extract(args, '\$.alter') = 'engine=innodb' and done='yes'"`;

is(
   $output + 0,
   2,
   '--history table updated'
);

is(
   $exit,
   0,
   'basic test with option --history finished OK when table already exists'
) or diag($output);

$output = `/tmp/12345/use -N -e "select count(*) from information_schema.tables where TABLE_SCHEMA='percona' and table_name='pt_osc_history'"`;
is(
   $output + 0,
   1,
   '--history table was created only once when option --history was provided'
);

$output = `/tmp/12345/use -N -e "select count(*) from percona.pt_osc_history where job_id=2 and lower_boundary=17 and upper_boundary=20"`;

is(
   $output + 0,
   1,
   'Lower and upper boundaries were updated when table altered with multiple chunks'
);

diag(`/tmp/12345/use -N -e "drop table percona.pt_osc_history"`);

($output, $exit) = full_output(
   sub { pt_online_schema_change::main(@args, "$dsn,D=pt_osc,t=t",
         '--alter', 'engine=innodb', '--execute', '--history', '--binary-index') }
);

is(
   $exit,
   0,
   'basic test with option --binary-index finished OK'
) or diag($output);

$output = `/tmp/12345/use -N -e "select count(*) from information_schema.tables where TABLE_SCHEMA='percona' and table_name='pt_osc_history'"`;
is(
   $output + 0,
   1,
   '--history table was created when option --history and --binary-index were provided'
);

$output = `/tmp/12345/use -e "show create table percona.pt_osc_history"`;
like(
   $output,
   qr/`lower_boundary` blob,\\n\s+`upper_boundary` blob/i,
   '--history table created with BLOB data type for boundary columns with --binary-index'
);

$output = `/tmp/12345/use -N -e "select count(*) from percona.pt_osc_history where db='pt_osc' and tbl='t' and altr='engine=innodb' and json_extract(args, '\$.alter') = 'engine=innodb' and done='yes'"`;

is(
   $output + 0,
   1,
   'Initial row with Job ID was inserted into --history table with --binary-index'
);

$output = `/tmp/12345/use -N -e "select count(*) from percona.pt_osc_history where job_id=1 and lower_boundary is null and upper_boundary is null"`;

is(
   $output + 0,
   1,
   'Lower and upper boundaries were not updated when table altered with single chunk and --binary-index'
);

($output, $exit) = full_output(
   sub { pt_online_schema_change::main(@args, "$dsn,D=pt_osc,t=t",
         '--alter', 'engine=innodb', '--execute', '--history', '--binary-index', '--chunk-size=4') }
);

is(
   $exit,
   0,
   'second run with option --binary-index finished OK'
) or diag($output);

$output = `/tmp/12345/use -N -e "select count(*) from information_schema.tables where TABLE_SCHEMA='percona' and table_name='pt_osc_history'"`;
is(
   $output + 0,
   1,
   '--history table was created only once with --binary-index'
);

$output = `/tmp/12345/use -N -e "select count(*) from percona.pt_osc_history where db='pt_osc' and tbl='t' and altr='engine=innodb' and json_extract(args, '\$.alter') = 'engine=innodb' and done='yes'"`;

is(
   $output + 0,
   2,
   '--history table with --binary-index updated'
);

$output = `/tmp/12345/use -N -e "select count(*) from percona.pt_osc_history where job_id=2 and lower_boundary=17 and upper_boundary=20"`;

is(
   $output + 0,
   1,
   'Lower and upper boundaries were updated when table altered with multiple chunks and --binary-index'
);

($output, $exit) = full_output(
   sub { pt_online_schema_change::main(@args, "$dsn,D=pt_osc,t=t",
         '--alter', 'engine=innodb', '--execute', '--history') }
);

isnt(
   $exit,
   0,
   'pt_osc with --history failed if table with the same name and different structure exists'
) or diag($output);

diag(`/tmp/12345/use -e "alter table percona.pt_osc_history add column foo int"`);

($output, $exit) = full_output(
   sub { pt_online_schema_change::main(@args, "$dsn,D=pt_osc,t=t",
         '--alter', 'engine=innodb', '--execute', '--history', '--binary-index') }
);

isnt(
   $exit,
   0,
   'pt_osc with --history and --binary-index failed if table with the same name and different structure exists'
) or diag($output);

# Custom table
($output, $exit) = full_output(
   sub { pt_online_schema_change::main(@args, "$dsn,D=pt_osc,t=t",
         '--alter', 'engine=innodb', '--execute', '--history',
         '--history-table=pt_1717.pt_1717_history') }
);

is(
   $exit,
   0,
   'basic test with option --history-table finished OK'
) or diag($output);

$output = `/tmp/12345/use -N -e "select count(*) from information_schema.tables where TABLE_SCHEMA='pt_1717' and table_name='pt_1717_history'"`;
is(
   $output + 0,
   1,
   'Custom --history table created'
);

$output = `/tmp/12345/use -N -e "select count(*) from pt_1717.pt_1717_history where job_id=1 and lower_boundary is null and upper_boundary is null"`;

is(
   $output + 0,
   1,
   'Lower and upper boundaries were not updated in custom history table when table altered with single chunk'
);

$output = `/tmp/12345/use -N -e "select count(*) from pt_1717.pt_1717_history where db='pt_osc' and tbl='t' and altr='engine=innodb' and json_extract(args, '\$.alter') = 'engine=innodb' and done='yes'"`;

is(
   $output + 0,
   1,
   'Initial row with Job ID was inserted custom into --history table'
);

($output, $exit) = full_output(
   sub { pt_online_schema_change::main(@args, "$dsn,D=pt_osc,t=t",
         '--alter', 'engine=innodb', '--execute', '--history',
         '--history-table=pt_1717.pt_1717_history', '--chunk-size=4') }
);

is(
   $exit,
   0,
   'basic test with option --history-table finished OK when table already exists'
) or diag($output);

$output = `/tmp/12345/use -N -e "select count(*) from information_schema.tables where TABLE_SCHEMA='pt_1717' and table_name='pt_1717_history'"`;

is(
   $output + 0,
   1,
   'Custom --history table was created only once'
);

$output = `/tmp/12345/use -N -e "select count(*) from pt_1717.pt_1717_history where db='pt_osc' and tbl='t' and altr='engine=innodb' and json_extract(args, '\$.alter') = 'engine=innodb' and done='yes'"`;

is(
   $output + 0,
   2,
   'Custom --history table updated'
);

$output = `/tmp/12345/use -N -e "select count(*) from pt_1717.pt_1717_history where job_id=2 and lower_boundary=17 and upper_boundary=20"`;

is(
   $output + 0,
   1,
   'Lower and upper boundaries in custom history table were updated when table altered with multiple chunks'
);

# #############################################################################
# Done.
# #############################################################################

$sb->wipe_clean($source_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
#
done_testing;

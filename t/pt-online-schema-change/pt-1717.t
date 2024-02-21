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
my $master_dbh = $sb->get_dbh_for('master');
my $slave_dbh  = $sb->get_dbh_for('slave1');

if ( !$master_dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
elsif ( !$slave_dbh ) {
   plan skip_all => 'Cannot connect to sandbox slave';
}

my @args   = qw(--set-vars innodb_lock_wait_timeout=3);
my $output = "";
my $dsn    = "h=127.1,P=12345,u=msandbox,p=msandbox";
my $exit   = 0;
my $sample = "t/pt-online-schema-change/samples";

$sb->load_file('master', "$sample/basic_no_fks_innodb.sql");

# First test option --history
# * - Test done for the development step
# ** - Test done for two development steps
# 1.** If table percona.pt_osc not created when option not specified
# 2. If table percona.pt_osc created when option present
# 2.1.** Default name
# 2.2.** Custom name
# 2.3.** Second run should not fail or modify this table (except inserting a row for new job)
# 2.4.** Case for binary index
# 2.5.** Second run for the binary index
# 2.6.** Case for invalid existing table
# 2.7.** Case for invalid existing table and binary index
# 3.** Inserting db, tbl, alter, args
# 4. Updating lower and upper boundaries
# 4.1. In situation when pt-osc finishes correctly
# 4.1.1.* `done` set to 'yes'
# 4.2. In failures
# 4.2.1. `done` set to 'no'

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

($output, $exit) = full_output(
   sub { pt_online_schema_change::main(@args, "$dsn,D=pt_osc,t=t",
         '--alter', 'engine=innodb', '--execute', '--history') }
);

is(
   $exit,
   0,
   'basic test with option --history finished OK'
) or diag($output);

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
   '--history table was created when option --history was provided only once'
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

($output, $exit) = full_output(
   sub { pt_online_schema_change::main(@args, "$dsn,D=pt_osc,t=t",
         '--alter', 'engine=innodb', '--execute', '--history', '--binary-index') }
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

$output = `/tmp/12345/use -N -e "select count(*) from pt_1717.pt_1717_history where db='pt_osc' and tbl='t' and altr='engine=innodb' and json_extract(args, '\$.alter') = 'engine=innodb' and done='yes'"`;

is(
   $output + 0,
   1,
   'Initial row with Job ID was inserted custom into --history table'
);

($output, $exit) = full_output(
   sub { pt_online_schema_change::main(@args, "$dsn,D=pt_osc,t=t",
         '--alter', 'engine=innodb', '--execute', '--history',
         '--history-table=pt_1717.pt_1717_history') }
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

# #############################################################################
# Done.
# #############################################################################

$sb->wipe_clean($master_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
#
done_testing;

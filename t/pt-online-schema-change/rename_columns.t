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

use Data::Dumper;
use PerconaTest;
use Sandbox;

require "$trunk/bin/pt-online-schema-change";

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $master_dbh = $sb->get_dbh_for('master');
my $slave_dbh  = $sb->get_dbh_for('slave1');

if ( !$master_dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
elsif ( !$slave_dbh ) {
   plan skip_all => 'Cannot connect to sandbox slave1';
}

# The sandbox servers run with lock_wait_timeout=3 and it's not dynamic
# so we need to specify --set-vars innodb_lock_wait_timeout-3 else the
# tool will die.
my $master_dsn = 'h=127.1,P=12345,u=msandbox,p=msandbox';
my @args       = (qw(--set-vars innodb_lock_wait_timeout=3));
my $output;
my $exit_status;
my $sample  = "t/pt-online-schema-change/samples/";

# ############################################################################
# https://bugs.launchpad.net/percona-toolkit/+bug/1068562
# pt-online-schema-change loses data when renaming columns
# ############################################################################

$sb->load_file('master', "$sample/data-loss-bug-1068562.sql");

($output, $exit_status) = full_output(
   sub { pt_online_schema_change::main(@args,
      "$master_dsn,D=bug1068562,t=simon",
      "--alter", "change old_column_name new_column_name varchar(255) NULL",
      qw(--execute)) },
);

ok(
   $exit_status,
   "Die if --execute without --no-check-alter"
) or diag($output);

like(
   $output,
   qr/Specify --no-check-alter to disable this check/,
   "--check-alter error message"
);

($output, $exit_status) = full_output(
   sub { pt_online_schema_change::main(@args,
      "$master_dsn,D=bug1068562,t=simon",
      "--alter", "change old_column_name new_column_name varchar(255) NULL",
      qw(--execute --no-check-alter)) },
);

my $rows = $master_dbh->selectall_arrayref("SELECT * FROM bug1068562.simon ORDER BY id");

is_deeply(
   $rows,
   [  [qw(1 a)], [qw(2 b)], [qw(3 c)] ],
   "bug1068562.simon: No data lost"
) or diag(Dumper($rows));

# #############################################################################
# Now try with sakila.city.
# #############################################################################

my $orig = $master_dbh->selectall_arrayref(q{SELECT city FROM sakila.city});

($output, $exit_status) = full_output(
   sub { pt_online_schema_change::main(@args,
      "$master_dsn,D=sakila,t=city",
      "--alter", "change column `city` `some_cities` varchar(50) NOT NULL",
      qw(--execute --alter-foreign-keys-method auto --no-check-alter)) },
);

is(
   $exit_status,
   0,
   "sakila.city: Exit status 0",
) or diag($output);

my $mod = $master_dbh->selectall_arrayref(q{SELECT some_cities FROM sakila.city});

is_deeply(
   $orig,
   $mod,
   "sakila.city: No data missing after first rename"
);

($output, $exit_status) = full_output(
   sub { pt_online_schema_change::main(@args,
      "$master_dsn,D=sakila,t=city",
      "--alter", "change column `some_cities` city varchar(50) NOT NULL",
      qw(--execute --alter-foreign-keys-method auto --no-check-alter)) },
);

my $mod2 = $master_dbh->selectall_arrayref(q{SELECT city FROM sakila.city});

is_deeply(
   $orig,
   $mod2,
   "sakila.city: No date missing after second rename"
);


# #############################################################################
# Try with sakila.staff
# #############################################################################

$orig = $master_dbh->selectall_arrayref(q{SELECT first_name, last_name FROM sakila.staff});

($output, $exit_status) = full_output(
   sub { pt_online_schema_change::main(@args,
      "$master_dsn,D=sakila,t=staff",
      "--alter", "change column first_name first_name_mod varchar(45) NOT NULL, change column last_name last_name_mod varchar(45) NOT NULL",
      qw(--execute --alter-foreign-keys-method auto --no-check-alter)) },
);

$mod = $master_dbh->selectall_arrayref(q{SELECT first_name_mod, last_name_mod FROM sakila.staff});

is_deeply(
   $orig,
   $mod,
   "sakila.staff: No columns went missing with a double rename"
);

($output, $exit_status) = full_output(
   sub { pt_online_schema_change::main(@args,
      "$master_dsn,D=sakila,t=staff",
      "--alter", "change column first_name_mod first_name varchar(45) NOT NULL, change column last_name_mod last_name varchar(45) NOT NULL",
      qw(--execute --alter-foreign-keys-method auto --no-check-alter)) },
);

$mod2 = $master_dbh->selectall_arrayref(q{SELECT first_name, last_name FROM sakila.staff});

is_deeply(
   $orig,
   $mod2,
   "sakila.staff: No columns went missing when renaming the columns back"
);


# #############################################################################
# --dry-run and other stuff
# #############################################################################

($output, $exit_status) = full_output(
   sub { pt_online_schema_change::main(@args,
      "$master_dsn,D=sakila,t=staff",
      "--alter", "change column first_name first_name_mod varchar(45) NOT NULL, change column last_name last_name_mod varchar(45) NOT NULL",
      qw(--dry-run --alter-foreign-keys-method auto)) },
);

is(
   $exit_status,
   0,
   "No error with --dry-run"
);

like(
   $output,
   qr/first_name to first_name_mod.+?last_name to last_name_mod/ms,
   "--dry-run warns about renaming columns"
);

# CHANGE COLUMN same_name same_name

($output, $exit_status) = full_output(
   sub { pt_online_schema_change::main(@args,
      "$master_dsn,D=sakila,t=staff",
      "--alter", "change column first_name first_name varchar(45) NOT NULL",
      qw(--execute --alter-foreign-keys-method auto)) },
);

unlike(
   $output,
   qr/fist_name to fist_name/,
   "No warning if CHANGE col col"
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;

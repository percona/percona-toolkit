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
# so we need to specify --lock-wait-timeout=3 else the tool will die.
my $master_dsn = 'h=127.1,P=12345,u=msandbox,p=msandbox';
my @args       = (qw(--lock-wait-timeout 3));
my $output;
my $exit_status;
my $sample  = "t/pt-online-schema-change/samples/";

# ############################################################################
# https://bugs.launchpad.net/percona-toolkit/+bug/994002
# pt-online-schema-change 2.1.1 doesn't choose the PRIMARY KEY
# ############################################################################
$sb->load_file('master', "$sample/pk-bug-994002.sql");

($output, $exit_status) = full_output(
   sub { pt_online_schema_change::main(@args,
      "$master_dsn,D=test,t=t",
      "--alter", "add column (foo int)",
      qw(--chunk-size 2 --dry-run --print)) },
);

# Must chunk the table to detect the next test correctly.
like(
   $output,
   qr/next chunk boundary/,
   "Bug 994002: chunks the table"
);

unlike(
   $output,
   qr/FORCE INDEX\(`guest_language`\)/,
   "Bug 994002: doesn't choose non-PK"
);

# ############################################################################
# https://bugs.launchpad.net/percona-toolkit/+bug/1002448
# ############################################################################
$sb->load_file('master', "$sample/bug-1002448.sql");

($output, $exit_status) = full_output(
    sub { pt_online_schema_change::main(@args,
            "$master_dsn,D=test1002448,t=table_name",
            "--alter", "add column (foo int)",
            qw(--chunk-size 2 --dry-run --print)) },
);


unlike $output,
    qr/\QThe original table `test1002448`.`table_name` does not have a PRIMARY KEY or a unique index which is required for the DELETE trigger/,
    "Bug 1002448: mistakenly uses indexes instead of keys";

# ############################################################################
# https://bugs.launchpad.net/percona-toolkit/+bug/1003315
# ############################################################################
$sb->load_file('master', "$sample/bug-1003315.sql");

# Have to use full_output here, because the error message may happen during
# cleanup, and so won't be caught by output().
($output, $exit_status) = full_output(
    sub { pt_online_schema_change::main(@args,
            "$master_dsn,D=test1003315,t=A",
            "--alter", "ENGINE=InnoDB",
            "--alter-foreign-keys-method", "auto",
            "--dry-run",
            qw(--chunk-size 2 --dry-run --print))
        
    },
);

is $exit_status, 0, "Bug 1003315: Correct exit value for a dry run";

unlike $output,
    qr/\QError updating foreign key constraints: Invalid --alter-foreign-keys-method:/,
    "Bug 1003315: No error when combining --alter-foreign-keys-method auto and --dry-run";

like $output,
    qr/\QNot updating foreign key constraints because this is a dry run./,
    "Bug 1003315: But now we do get an explanation from --dry-run";

# ############################################################################
# This fakes the conditions to trigger the chunk index error
# ############################################################################
{
   my $o = new OptionParser(file => "$trunk/bin/pt-table-checksum");
   $o->get_specs();
   no warnings;
   local *pt_online_schema_change::explain_statement = sub {
      return { key => 'some_key' }
   };
   {
      package PerconaTest::Fake::NibbleIterator;
      sub AUTOLOAD {
          our $AUTOLOAD = $AUTOLOAD;
          return if $AUTOLOAD =~ /one_nibble/;
          return { lower => [], upper => [] }
      }
   }

   eval {
      pt_online_schema_change::nibble_is_safe(
         Cxn   => 1,
         tbl   => {qw( db some_db tbl some_table )},
         NibbleIterator => bless({}, "PerconaTest::Fake::NibbleIterator"),
         OptionParser   => $o,
      );
   };
   
   like(
      $EVAL_ERROR,
      qr/Error copying rows at chunk.*because MySQL chose/,
      "Dies if MySQL isn't using the chunk index"
   );

   $o->set('quiet', 1);
   eval {
      pt_online_schema_change::nibble_is_safe(
         Cxn   => 1,
         tbl   => {qw( db some_db tbl some_table )},
         NibbleIterator => bless({}, "PerconaTest::Fake::NibbleIterator"),
         OptionParser   => $o,
      );
   };
   
   like(
      $EVAL_ERROR,
      qr/Error copying rows at chunk.*because MySQL chose/,
      "...even if --quiet was specified",
   );
}

# ############################################################################
# Bug 1041372: ptc-osc and long table names
# https://bugs.launchpad.net/percona-toolkit/+bug/1041372
# ############################################################################
my $orig_tbl = 'very_very_very_very_very_very_very_very_very_long_table_name';  

$master_dbh->do(q{DROP DATABASE IF EXISTS `bug_1041372`});
$master_dbh->do(q{CREATE DATABASE `bug_1041372`});

for my $i ( 0..4 ) {
   my $tbl = $orig_tbl . ("a" x $i);
   $master_dbh->do(qq{create table `bug_1041372`.$tbl (a INT NOT NULL AUTO_INCREMENT PRIMARY KEY )});
   $master_dbh->do(qq{insert into `bug_1041372`.$tbl values (1), (2), (3), (4), (5)});

   ($output) = full_output(sub { pt_online_schema_change::main(@args,
                                 '--alter', "ADD COLUMN ptosc INT",
                                 '--execute', "$master_dsn,D=bug_1041372,t=$tbl")});

   like(
      $output,
      qr/\QSuccessfully altered `bug_1041372`.`$tbl`/,
      "pt-osc works on long table names (length " . length($tbl) . ")"
   );
}

my $triggers = $master_dbh->selectall_arrayref(qq{SHOW TRIGGERS FROM `bug_1041372`});
is_deeply(
   $triggers,
   [],
   "No triggers left for long table names"
) or diag(Dumper($triggers));

$master_dbh->do(q{DROP DATABASE IF EXISTS `bug_1041372`});

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
   "Bug 1068562: --execute dies if renaming a column without --no-check-alter"
);

like(
   $output,
   qr/Specify --no-check-alter to disable this check/,
   "--check-alter works"
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
   "Bug 1068562: no data lost"
) or diag(Dumper($rows));

# Now try with sakila.city.

my $orig = $master_dbh->selectall_arrayref(q{SELECT city FROM sakila.city});

($output, $exit_status) = full_output(
   sub { pt_online_schema_change::main(@args,
      "$master_dsn,D=sakila,t=city",
      "--alter", "change column `city` `some_cities` varchar(50) NOT NULL",
      qw(--execute --alter-foreign-keys-method auto --no-check-alter)) },
);

ok(
   !$exit_status,
   "Bug 1068562: Renamed column correctly"
);

my $mod = $master_dbh->selectall_arrayref(q{SELECT some_cities FROM sakila.city});

is_deeply(
   $orig,
   $mod,
   "Bug 1068562: No columns went missing"
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
   "Bug 1068562: No columns went missing after a second rename"
);

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
   "Bug 1068562: No columns went missing with a double rename"
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
   "Bug 1068562: No columns went missing when renaming the columns back"
);

($output, $exit_status) = full_output(
   sub { pt_online_schema_change::main(@args,
      "$master_dsn,D=sakila,t=staff",
      "--alter", "change column first_name first_name_mod varchar(45) NOT NULL, change column last_name last_name_mod varchar(45) NOT NULL",
      qw(--dry-run --alter-foreign-keys-method auto)) },
);

ok(
   !$exit_status,
   "Bug 1068562: No error with --dry-run"
);

like(
   $output,
   qr/first_name to first_name_mod, last_name to last_name_mod/ms,
   "Bug 1068562: --dry-run warns about renaming columns"
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
   "Bug 1068562: change column same_name same_name doesn't warn about renames"
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");

done_testing;

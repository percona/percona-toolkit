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
# so we need to specify --set-vars innodb_lock_wait_timeout=3 else the
# tool will die.
my $master_dsn = 'h=127.1,P=12345,u=msandbox,p=msandbox';
my @args       = (qw(--set-vars innodb_lock_wait_timeout=3));
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


unlike(
   $output,
   qr/\QThe new table `test1002448`.`_table_name_new` does not have a PRIMARY KEY or a unique index which is required for the DELETE trigger/,
   "Bug 1002448: mistakenly uses indexes instead of keys"
);

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

is(
   $exit_status,
   0,
   "Bug 1003315: Correct exit value for a dry run"
);

unlike(
   $output,
    qr/\QError updating foreign key constraints: Invalid --alter-foreign-keys-method:/,
    "Bug 1003315: No error when combining --alter-foreign-keys-method auto and --dry-run"
);

like(
   $output,
   qr/\QNot updating foreign key constraints because this is a dry run./,
   "Bug 1003315: But now we do get an explanation from --dry-run"
);

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

   ($output) = full_output(sub {
      pt_online_schema_change::main(@args,
          '--alter', "ADD COLUMN ptosc INT",
          '--execute', "$master_dsn,D=bug_1041372,t=$tbl")
   });

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
# https://bugs.launchpad.net/percona-toolkit/+bug/1062324
# pt-online-schema-change sets bad DELETE trigger when changing Primary Key
# ############################################################################
$sb->load_file('master', "$sample/del-trg-bug-1062324.sql");

{
   # pt-osc has no --no-drop-triggers option, so we hijack its sub.
   no warnings;
   local *pt_online_schema_change::drop_triggers = sub { return };

   # Run the tool but leave the original and new tables as-is,
   # and leave the triggers.
   ($output, $exit_status) = full_output(
      sub { pt_online_schema_change::main(@args,
         "$master_dsn,D=test,t=t1",
         "--alter", "drop key 2bpk, drop key c3, drop primary key, drop c1, add primary key (c2, c3(4)), add key (c3(4))",
         qw(--no-check-alter --execute --no-drop-new-table --no-swap-tables)) },
   );

   # Since _t1_new no longer has the c1 column, the bug caused this
   # query to throw "ERROR 1054 (42S22): Unknown column 'test._t1_new.c1'
   # in 'where clause'".
   eval {
      $master_dbh->do("DELETE FROM test.t1 WHERE c1=1");
   };
   is(
      $EVAL_ERROR,
      "",
      "No delete trigger error after altering PK (bug 1062324)"
   ) or diag($output);

   # The original row was (c1,c2,c3) = (1,1,1).  We deleted where c1=1,
   # so the row where c2=1 AND c3=1 should no longer exist.
   my $row = $master_dbh->selectrow_arrayref("SELECT * FROM test._t1_new WHERE c2=1 AND c3=1");
   is(
      $row,
      undef,
      "Delete trigger works after altering PK (bug 1062324)"
   );

   # Another instance of this bug:
   # https://bugs.launchpad.net/percona-toolkit/+bug/1103672
   $sb->load_file('master', "$sample/del-trg-bug-1103672.sql");

   ($output, $exit_status) = full_output(
      sub { pt_online_schema_change::main(@args,
         "$master_dsn,D=test,t=t1",
         "--alter", "drop primary key, add column _id int unsigned not null primary key auto_increment FIRST",
         qw(--no-check-alter --execute --no-drop-new-table --no-swap-tables)) },
   );

   eval {
      $master_dbh->do("DELETE FROM test.t1 WHERE id=1");
   };
   is(
      $EVAL_ERROR,
      "",
      "No delete trigger error after altering PK (bug 1103672)"
   ) or diag($output);

   $row = $master_dbh->selectrow_arrayref("SELECT * FROM test._t1_new WHERE id=1");
   is(
      $row,
      undef,
      "Delete trigger works after altering PK (bug 1103672)"
   );
}

# #############################################################################
# Something like http://bugs.mysql.com/bug.php?id=45694 means we should not
# use LOCK IN SHARE MODE with MySQL 5.0.
# #############################################################################
$sb->load_file('master', "$sample/basic_no_fks_innodb.sql");

($output, $exit_status) = full_output(
    sub { pt_online_schema_change::main(@args,
            "$master_dsn,D=pt_osc,t=t",
            "--alter", "add column (foo int)",
            qw(--execute --print))
   },
);

if ( $sandbox_version eq '5.0' ) {
   unlike(
      $output,
      qr/LOCK IN SHARE MODE/,
      "No LOCK IN SHARE MODE for MySQL $sandbox_version"
   );
}
else {
   like(
      $output,
      qr/LOCK IN SHARE MODE/,
      "LOCK IN SHARE MODE for MySQL $sandbox_version",
   );
}

# ############################################################################
# https://bugs.launchpad.net/percona-toolkit/+bug/1171653
# 
# ############################################################################
$sb->load_file('master', "$sample/utf8_charset_tbl.sql");

($output, $exit_status) = full_output(
    sub { pt_online_schema_change::main(@args,
      "$master_dsn,D=test1171653,t=t",
      "--alter", "drop column foo",
      qw(--execute --print))
   },
);

my $row = $master_dbh->selectrow_arrayref("SHOW CREATE TABLE test1171653.t");

like(
   $row->[1],
   qr/DEFAULT CHARSET=utf8/,
   "Bug 1171653: table charset is not preserved"
);

# #############################################################################
# https://bugs.launchpad.net/percona-toolkit/+bug/1188264
# pt-online-schema-change error copying rows: Undefined subroutine
# &pt_online_schema_change::get
# #############################################################################

# In exec_nibble() we had:
#    if ( get('statistics') ) {
#       $err .= "but further occurrences will be reported "
#             . "by --statistics when the tool finishes.\n";
#    }
# which is called when copying rows causes a MySQL warning
# for the first time.  So to test this code path, we need to
# cause a MySQL warning while copying rows.

$sb->load_file('master', "$sample/basic_no_fks_innodb.sql");
$master_dbh->do("INSERT INTO pt_osc.t VALUES (null, 'This string will be too long after we modify the table so it will cause a warning about the value being truncated in the new table.  The other column values are a single character.', NOW())");

($output, $exit_status) = full_output(
    sub { pt_online_schema_change::main(@args,
      "$master_dsn,D=pt_osc,t=t",
      "--alter", "modify c varchar(8)",
      qw(--execute --print))
   },
);

is(
   $exit_status,
   0,
   "Bug 1188264: 0 exit"
);

unlike(
   $output,
   qr/Undefined subroutine/i,
   "Bug 1188264: no undefined subroutine"
);

like(
   $output,
   qr/error 1265/,  # Data truncated for column 'c' at row 21
   "Bug 1188264: warning about expected MySQL error 1265"
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;

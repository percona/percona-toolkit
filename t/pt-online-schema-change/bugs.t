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
# This fakes the conditions to trigger
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
   
   is(
      $EVAL_ERROR,
      '',
      "..unless --quiet was specified",
   );
}

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");

done_testing;

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
else {
   plan tests => 3;
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

$output = output(
   sub { $exit_status = pt_online_schema_change::main(@args,
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

$output = output(
    sub { pt_online_schema_change::main(@args,
            "$master_dsn,D=test1002448,t=table_name",
            "--alter", "add column (foo int)",
            qw(--chunk-size 2 --dry-run --print)) },
);


unlike $output,
    qr/\QThe original table `test1002448`.`table_name` does not have a PRIMARY KEY or a unique index which is required for the DELETE trigger/,
    "Bug 1002448: mistakenly uses indexes instead of keys";

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
exit;

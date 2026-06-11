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

if ( $sandbox_version ge '5.6' ) {
   plan skip_all => 'Cannot disable InnoDB in MySQL 5.6';
}

diag(`$trunk/sandbox/stop-sandbox 12348 >/dev/null`);
diag(`SKIP_INNODB=1 $trunk/sandbox/start-sandbox source 12348 >/dev/null`);

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $source_dbh = $sb->get_dbh_for('source1');

if ( !$source_dbh ) {
   plan skip_all => 'Cannot connect to sandbox source 12348';
}

my $source_dsn = 'h=127.1,P=12348,u=msandbox,p=msandbox';
my @args       = (qw(--set-vars innodb_lock_wait_timeout=3), '--max-load', ''); 

my ($output, $retval) = full_output(
   sub { pt_online_schema_change::main(@args,
      "$source_dsn,D=mysql,t=user", "--alter", "add column (foo int)",
      qw(--dry-run)) },
);

like(
   $output,
   qr/`mysql`.`user`/,
   "Ran without InnoDB (bug 994010)"
);

is(
   $retval,
   0,
   "0 exit status (bug 994010)"
);

# #############################################################################
# Done.
# #############################################################################
diag(`$trunk/sandbox/stop-sandbox 12348 >/dev/null`);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;

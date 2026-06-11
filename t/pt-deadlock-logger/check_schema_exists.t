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
require "$trunk/bin/pt-deadlock-logger";

my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('source');

my ($output, $exit_status) = full_output(
   sub {
      pt_deadlock_logger::main(
         "h=127.1,D=non_existent_db,u=msandbox,p=msandbox",
         qw(--clear-deadlocks non_existent_db.make_deadlock --port 12345),
         qw(--iterations 1)
      )
   }
);

is(
   $exit_status,
   2,
   'Dies when connects to non existent database'
);

like(
   $output,
   qr/Unknown database 'non_existent_db'/,
   'Error printed when connects to non existent database'
);
# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;

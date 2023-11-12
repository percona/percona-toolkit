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
use Time::HiRes qw(time);

use PerconaTest;
use Sandbox;
use Data::Dumper;
require "$trunk/bin/pt-archiver";

my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $master_dbh = $sb->get_dbh_for('master');
my $slave1_dbh = $sb->get_dbh_for('slave1');

if ( !$master_dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
elsif ( !$slave1_dbh ) {
   plan skip_all => 'Cannot connect to sandbox slave1';
}

my $cnf  = "/tmp/12345/my.sandbox.cnf";
my $cmd  = "$trunk/bin/pt-archiver";
my @args = qw(--where 1=1);

$sb->create_dbs($master_dbh, ['test']);
$sb->load_file('master', 't/pt-archiver/samples/table1.sql');
$sb->wait_for_slaves();

$master_dbh->do('set global innodb_lock_wait_timeout=1');

$master_dbh->do('begin');
$master_dbh->do('select * from test.table_1 for update;');

my ($output, $exit_val) = full_output(sub {pt_archiver::main(@args, '--source', "D=test,t=table_1,F=$cnf", qw(--purge)) });

is(
   $exit_val,
   0,
   'No rollback on non-existent destination'
);

unlike(
   $output,
   qr/Can't call method "rollback" on an undefined value/,
   'No rollback on non-existent destination'
) or diag($output);

# #############################################################################
# Done.
# #############################################################################
$master_dbh->do('set global innodb_lock_wait_timeout=DEFAULT');

$sb->wipe_clean($master_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");

done_testing;

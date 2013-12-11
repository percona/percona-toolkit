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
my $sample     = "t/pt-online-schema-change/samples/";
my $plugin     = "$trunk/$sample/plugins";
my $output;
my $exit_status;

# ############################################################################
# https://bugs.launchpad.net/percona-toolkit/+bug/1171653
# 
# ############################################################################
$sb->load_file('master', "$sample/basic_no_fks.sql");

($output, $exit_status) = full_output(
   sub { pt_online_schema_change::main(@args,
      "$master_dsn,D=pt_osc,t=t",
      "--alter", "CHARACTER SET utf8, MODIFY c CHAR(128) CHARACTER SET utf8",
      '--plugin', "$plugin/show_create_new_table.pm",
      qw(--quiet --execute)) },
);

my @create = split("\n\n", $output);

like(
   $create[1] || '',
   qr/DEFAULT CHARSET=utf8/,
   "Can alter charset of new table"
) or diag($output);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;

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
require "$trunk/bin/pt-table-sync";

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $master_dbh = $sb->get_dbh_for('master');
my $slave_dbh  = $sb->get_dbh_for('slave1'); 

if ( !$master_dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
elsif ( !$slave_dbh ) {
   plan skip_all => 'Cannot connect to sandbox slave';
} elsif ($sandbox_version lt '5.7') {
   plan skip_all => 'Only on MySQL 5.7+';
} else {
   plan tests => 2;
}

my ($master1_dbh, $master1_dsn) = $sb->start_sandbox(
   server => 'chan_master1',
   type   => 'master',
);
my ($master2_dbh, $master2_dsn) = $sb->start_sandbox(
   server => 'chan_master2',
   type   => 'master',
);
my ($slave1_dbh, $slave1_dsn) = $sb->start_sandbox(
   server => 'chan_slave1',
   type   => 'master',
);
my $slave1_port = $sb->port_for('chan_slave1');

$sb->load_file('chan_master1', "sandbox/gtid_on.sql", undef, no_wait => 1);
$sb->load_file('chan_master2', "sandbox/gtid_on.sql", undef, no_wait => 1);
$sb->load_file('chan_slave1', "sandbox/slave_channels.sql", undef, no_wait => 1);
                                                          
my @args = qw(--execute --no-foreign-key-checks --verbose --databases=sakila --tables=actor --sync-to-master --channel=masterchan1);
my $exit_status;

my $output = output(
   sub { $exit_status = pt_table_sync::main(@args, $slave1_dsn) },
   stderr => 1,
);

like (
    $output,
    qr/sakila.actor/,
    'Synced actor table'
);

$sb->stop_sandbox(qw(chan_master1 chan_master2 chan_slave1));


# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;

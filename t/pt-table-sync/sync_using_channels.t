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
my $source_dbh = $sb->get_dbh_for('source');
my $replica_dbh  = $sb->get_dbh_for('replica1'); 

if ( !$source_dbh ) {
   plan skip_all => 'Cannot connect to sandbox source';
}
elsif ( !$replica_dbh ) {
   plan skip_all => 'Cannot connect to sandbox replica';
} elsif ($sandbox_version lt '5.7') {
   plan skip_all => 'Only on MySQL 5.7+';
} else {
   plan tests => 2;
}

my ($source1_dbh, $source1_dsn) = $sb->start_sandbox(
   server => 'chan_source1',
   type   => 'source',
);
my ($source2_dbh, $source2_dsn) = $sb->start_sandbox(
   server => 'chan_source2',
   type   => 'source',
);
my ($replica1_dbh, $replica1_dsn) = $sb->start_sandbox(
   server => 'chan_replica1',
   type   => 'source',
);
my $replica1_port = $sb->port_for('chan_replica1');

if ( $sandbox_version lt '8.1' ) {
   $sb->load_file('chan_source1', "sandbox/gtid_on-legacy.sql", undef, no_wait => 1);
   $sb->load_file('chan_source2', "sandbox/gtid_on-legacy.sql", undef, no_wait => 1);
   $sb->load_file('chan_replica1', "sandbox/replica_channels-legacy.sql", undef, no_wait => 1);
} else {
   $sb->load_file('chan_source1', "sandbox/gtid_on.sql", undef, no_wait => 1);
   $sb->load_file('chan_source2', "sandbox/gtid_on.sql", undef, no_wait => 1);
   $sb->load_file('chan_replica1', "sandbox/replica_channels.sql", undef, no_wait => 1);
}
                                                          
my @args = qw(--execute --no-foreign-key-checks --verbose --databases=sakila --tables=actor --sync-to-source --channel=sourcechan1);
my $exit_status;

my $output = output(
   sub { $exit_status = pt_table_sync::main(@args, $replica1_dsn) },
   stderr => 1,
);

like (
    $output,
    qr/sakila.actor/,
    'Synced actor table'
) or diag($output);

$sb->stop_sandbox(qw(chan_source1 chan_source2 chan_replica1));


# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($source_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;

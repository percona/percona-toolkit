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

# Hostnames make testing less accurate.  Tests need to see
# that such-and-such happened on specific slave hosts, but
# the sandbox servers are all on one host so all slaves have
# the same hostname.
$ENV{PERCONA_TOOLKIT_TEST_USE_DSN_NAMES} = 1;

use PerconaTest;
use Sandbox;
require "$trunk/bin/pt-config-diff";

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $node1 = $sb->get_dbh_for('node1');
my $node2 = $sb->get_dbh_for('node2');
my $node3 = $sb->get_dbh_for('node3');

if ( !$node1 ) {
   plan skip_all => 'Cannot connect to cluster node1';
}
elsif ( !$node2 ) {
   plan skip_all => 'Cannot connect to cluster node2';
}
elsif ( !$node3 ) {
   plan skip_all => 'Cannot connect to cluster node3';
}
elsif ( !$sb->is_cluster_mode ) {
   plan skip_all => "PXC tests";
}

my $node1_dsn = $sb->dsn_for('node1');
my $node2_dsn = $sb->dsn_for('node2');

my $output = output(sub { pt_config_diff::main($node1_dsn, $node2_dsn) });

like(
   $output,
   qr/gcache.dir .+\ngcache.name/,
   "pt-config-diff parses & detects differences in each member of wsrep_provider_options"
);

$output = output(sub { pt_config_diff::main($node1_dsn, "$trunk/t/pt-config-diff/samples/pxc.cnf") });

like(
   $output,
   qr/pc.ignore_sb\s*false\s*true/,
   "wsrep_provider_options, node vs config file"
);



done_testing;

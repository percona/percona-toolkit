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
# that such-and-such happened on specific replica hosts, but
# the sandbox servers are all on one host so all replicas have
# the same hostname.
$ENV{PERCONA_TOOLKIT_TEST_USE_DSN_NAMES} = 1;

use PerconaTest;
use Sandbox;
require "$trunk/bin/pt-table-checksum";

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $node1 = $sb->get_dbh_for('node1');
my $sb_version = VersionParser->new($node1);
my $node2 = $sb->get_dbh_for('node2');
my $node3 = $sb->get_dbh_for('node3');

my %checks = (
    'Cannot connect to cluster node1' => !$node1,
    'Cannot connect to cluster node2' => !$node2,
    'Cannot connect to cluster node3' => !$node3,
    'PXC tests'                       => !$sb->is_cluster_mode,
);

for my $message (keys %checks) {
    if ( $checks{$message} ) {
        plan skip_all => $message;
    }
}

my $node1_dsn = $sb->dsn_for('node1');
my @args      = ($node1_dsn, qw(--databases pt-2400 --tables apple),
                             qw(--recursion-method none),
                             qw(--replicate percona.checksums --create-replicate-table --empty-replicate-table )
                );
my $sample  = "t/pt-table-checksum/samples/";

$sb->load_file('node1', "$sample/pt-2400.sql");

my ($output, $error) = full_output(
   sub { pt_table_checksum::main(@args) },
   stderr => 1,
);

unlike(
   $output,
   qr/Immediately starting the version comment after the version number is deprecated and may change behavior in a future release. Please insert a white-space character after the version number./,
   "No typo in version comment"
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($node1);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;

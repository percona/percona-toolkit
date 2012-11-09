#!/usr/bin/perl

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

use Sandbox;
use OptionParser;
use DSNParser;
use Quoter;
use PerconaTest;
use Cxn;
use VersionParser;

use Percona::XtraDB::Cluster;

my $q   = new Quoter();
my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $master_dbh = $sb->get_dbh_for('master');

my $cluster = Percona::XtraDB::Cluster->new();

if ( !$master_dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}

my $o  = new OptionParser(description => 'Cxn');
$o->get_specs("$trunk/bin/pt-table-checksum");
$o->get_opts();
$dp->prop('set-vars', $o->get('set-vars'));

sub make_cxn {
   my (%args) = @_;
   $o->get_opts();
   return new Cxn(
      OptionParser => $o,
      DSNParser    => $dp,
      %args,
   );
}

local @ARGV = ();
$o->get_opts();

diag("Starting master1");
$sb->start_sandbox("master", "master1");

my ($master_cxn, $slave1_cxn, $master1_cxn)
   = map {
         my $cxn = make_cxn( dsn_string => $sb->dsn_for($_) );
         $cxn->connect();
         $cxn;
   } qw( master slave1 master1 );

for my $cxn ( $master_cxn, $slave1_cxn, $master1_cxn ) {
   ok(
      !$cluster->is_cluster_node($cxn),
      "is_cluster_node works correctly for non-nodes " . $cxn->name
   );
}

ok($cluster->is_master_of($master_cxn, $slave1_cxn), "is_master_of(master, slave1) is true");
ok(!$cluster->is_master_of($slave1_cxn, $master_cxn), "is_master_of(slave1, master) is false");

diag($sb->stop_sandbox("master1"));

# #############################################################################
# Done.
# #############################################################################
$master_dbh->disconnect() if $master_dbh;
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
exit;

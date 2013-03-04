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
my $db_flavor = VersionParser->new($master_dbh)->flavor();

if ( $db_flavor =~ /XtraDB Cluster/ ) {
   plan skip_all => "Non-PXC tests";
}
elsif ( !$master_dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}

my $o = new OptionParser(
   description => 'Cxn',
   file        => "$trunk/bin/pt-table-checksum",
);
$o->get_specs("$trunk/bin/pt-table-checksum");
$o->get_opts();

# In 2.1, these tests did not set innodb_lock_wait_timeout because
# it was not a --set-vars default but rather its own option handled
# by/in the tool.  In 2.2, the var is a --set-vars default, which
# means it will cause a warning on 5.0 and 5.1, so we remoe the var
# to remove the warning.
my $set_vars = $o->set_vars();
delete $set_vars->{innodb_lock_wait_timeout};
delete $set_vars->{lock_wait_timeout};
$dp->prop('set-vars', $set_vars);

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
$sb->start_sandbox(type => "master", server => "master1");

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

diag($sb->stop_sandbox("master1"));

# #############################################################################
# Done.
# #############################################################################
$master_dbh->disconnect() if $master_dbh;
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
exit;

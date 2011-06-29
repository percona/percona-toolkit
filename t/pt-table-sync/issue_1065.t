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

use MaatkitTest;
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
}
else {
   plan tests => 1;
}

my $output;
my @args = ('--sync-to-master', 'h=127.1,P=12346,u=msandbox,p=msandbox',
            qw(-t sakila.rental --print --execute --no-check-triggers));

# #############################################################################
# Issue 1065: mk-table-sync --algorithm seems to be case-sensitive
# #############################################################################
$slave_dbh->do('delete from sakila.rental limit 1');

$output = output(
   sub { pt_table_sync::main(@args, qw(--algo chunk)) },
);
like(
   $output,
   qr/REPLACE INTO `sakila`.`rental`/,
   "Case-insensitive --algorithm"
);

# #############################################################################
# Done.
# #############################################################################
exit;

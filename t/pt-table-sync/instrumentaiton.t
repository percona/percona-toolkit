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
}
else {
   plan tests => 2;
}

my $output = '';
my @args   = (qw(--verbose --print --sync-to-master), 'h=127.1,P=12346,u=msandbox,p=msandbox');

# #############################################################################
# Issue 377: Make mk-table-sync print start/end times
# #############################################################################
$output = output(
   sub { pt_table_sync::main(@args, qw(-t mysql.user)) }
);
like(
   $output,
   qr/#\s+0\s+0\s+0\s+0\s+Nibble\s+
   \d\d:\d\d:\d\d\s+
   \d\d:\d\d:\d\d\s+
   0\s+mysql.user/x,
   "Server time printed with --verbose (issue 377)"
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
$sb->wipe_clean($slave_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;

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
require "$trunk/bin/pt-table-checksum";

my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
else {
   plan tests => 1;
}

my $output;
my $cnf = '/tmp/12345/my.sandbox.cnf';

# #############################################################################
# Issue 947: mk-table-checksum crashes if h DSN part is not given
# #############################################################################

$output = output(
   sub { pt_table_checksum::main("F=$cnf", qw(-d mysql -t user)) },
   stderr => 1,
);
like(
   $output,
   qr/mysql\s+user\s+0/,
   "Doesn't crash if no h DSN part (issue 947)"
);

# #############################################################################
# Done.
# #############################################################################
exit;

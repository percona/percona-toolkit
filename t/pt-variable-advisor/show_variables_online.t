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
shift @INC;  # These shifts are required for tools that use base and derived
shift @INC;  # classes.  See mk-query-digest/t/101_slowlog_analyses.t
shift @INC;
require "$trunk/bin/pt-variable-advisor";

my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');

if ( !$dbh ) {
   plan skip_all => "Cannot connect to sandbox master";
}
else {
   plan tests => 2;
}

# #############################################################################
# SHOW VARIABLES from the sandbox server.
# #############################################################################
my @args   = qw(F=/tmp/12345/my.sandbox.cnf);
my $output = "";

$output = output(
   sub { pt_variable_advisor::main(@args) },
);
like(
   $output,
   qr/port: The server is listening on a non-default port/,
   "Get variables from host"
);

$output = output(
   sub { pt_variable_advisor::main(@args, qw(--source-of-variables MYSQL)) },
);
like(
   $output,
   qr/port: The server is listening on a non-default port/,
   "Explicit --source-of-variables MYSQL"
);

# #############################################################################
# Done.
# #############################################################################
exit;

#!/usr/bin/env perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More tests => 4;

use PerconaTest;
use Sandbox;
require "$trunk/bin/pt-query-profiler";

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');

my $cnf = '/tmp/12345/my.sandbox.cnf';
my $cmd = "$trunk/bin/pt-query-profiler -F $cnf ";
my $mysql = $sb->_use_for('master');

my $output;

SKIP: {
   skip 'Sandbox master does not have the sakila database', 3
      unless $dbh && @{$dbh->selectcol_arrayref('SHOW DATABASES LIKE "sakila"')};

   $output = `echo "select * from sakila.film" | $cmd`;
   like(
      $output,
      qr{Questions\s+1},
      'It lives with input on STDIN',
   );

   $output = `$cmd -vvv --innodb $trunk/t/pt-query-profiler/samples/sample.sql`;
   like(
      $output,
      qr{Temp files\s+0},
      'It lives with verbosity, InnoDB, and a file input',
   );
   like(
      $output,
      qr{Handler _+ InnoDB},
      'I found InnoDB stats',
   );

   $sb->wipe_clean($dbh);
}

# #########################################################################
# Issue 391: Add --pid option to all scripts
# #########################################################################
`touch /tmp/mk-script.pid`;
$output = `$cmd -vvv --innodb sample.sql --pid /tmp/mk-script.pid 2>&1`;
like(
   $output,
   qr{PID file /tmp/mk-script.pid already exists},
   'Dies if PID file already exists (issue 391)'
);
`rm -rf /tmp/mk-script.pid`;

exit;

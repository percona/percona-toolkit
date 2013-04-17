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
require "$trunk/bin/pt-index-usage";

use Sandbox;
my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
if ( !@{ $dbh->selectall_arrayref("show databases like 'sakila'") } ) {
   plan skip_all => "Sakila database is not loaded";
}

my $cnf     = '/tmp/12345/my.sandbox.cnf';
my @args    = ('-F', $cnf);
my $samples = "t/pt-index-usage/samples/";
my $output;

# This query doesn't use indexes so there's an unused PK and
# an unused secondary index.  Only the secondary index should
# be printed since dropping PKs is not suggested by default.
ok(
   no_diff(
      sub {
          pt_index_usage::main(@args,
            "$trunk/$samples/slow001.txt");
      },
      "$samples/slow001-report.txt"),
   'A simple query that does not use any indexes',
);

# Same test as above but with --drop all to suggest dropping
# the PK.  The PK is printed separately.
ok(
   no_diff(
      sub {
          pt_index_usage::main(@args, qw(--drop all),
            "$trunk/$samples/slow001.txt");
      },
      "$samples/slow001-report-drop-all.txt"),
   '--drop all includes primary key on separate line',
);

# This query uses the primary key so there's one unused secondary index.
ok(
   no_diff(
      sub {
          pt_index_usage::main(@args,
            "$trunk/$samples/slow002.txt");
      },
      "$samples/slow002-report.txt"),
   'A simple query that uses the primary key',
);

# This query uses a secondary index which makes the primary key
# look unused.  The output should be blank because dropping the
# PK isn't suggested by default and there's no other unused indexes.
$output = output(
   sub { pt_index_usage::main(@args, "$trunk/$samples/slow003.txt") },
);
is(
   $output,
   '',
   'A simple query that uses a secondary index',
);

# This query uses the pk on a table with two other indexes, so those
# indexes are printed.
ok(
   no_diff(
      sub {
          pt_index_usage::main(@args,
            "$trunk/$samples/slow005.txt");
      },
      "$samples/slow005-report.txt"),
   'Drop multiple indexes',
);

# #############################################################################
# Capture errors, and ensure that statement blacklisting works OK.
# #############################################################################
$output = output(
   sub { pt_index_usage::main(@args, "$trunk/$samples/slow004.txt") },
   stderr => 1,
);
my @errs = $output =~ m/DBD::mysql::db selectall_arrayref failed/g;
is(
   scalar @errs,
   1,
   'Failing statement was blacklisted'
);


# #############################################################################
# Issue 1118: mk-index-usage doesn't have a --database option
# #############################################################################
ok(
   no_diff(
      sub {
          pt_index_usage::main(@args, qw(-D sakila),
            "$trunk/$samples/slow006.txt");
      },
      "$samples/slow006-report.txt"),
   '--database (-D) for default db'
);

$output = output(
   sub {
      pt_index_usage::main(@args, qw(-q),
         "$trunk/$samples/slow006.txt");
   },
);
is(
   $output,
   "",
   'No output without default db'
);

# https://bugs.launchpad.net/percona-toolkit/+bug/1028614
$dbh->do("CREATE DATABASE IF NOT EXISTS z");
$dbh->do("CREATE TABLE z.t (id int)");

ok(
   no_diff(
      sub { pt_index_usage::main(@args, qw(-D sakila),
               "$trunk/$samples/slow006.txt") },
      "$samples/slow006-report.txt"
   ),
   '--database is kept (bug 1028614)'
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
exit;

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
require "$trunk/bin/pt-archiver";

my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
else {
   plan tests => 3;
}

my $output;
my $rows;
my $cnf = "/tmp/12345/my.sandbox.cnf";

$sb->create_dbs($dbh, ['test']);

# #############################################################################
# Issue 655: Using --primary-key-only on a table without a primary key causes
# perl error
# #############################################################################
$dbh->do('CREATE TABLE test.t (i int)');
$output = output(
   sub { pt_archiver::main(qw(--where 1=1), "--source", "F=$cnf,D=test,t=t", qw(--purge --primary-key-only)) },
   stderr => 1,
);
unlike(
   $output,
   qr/undefined value/,
   'No error using --primary-key-only on table without pk (issue 655)'
);
like(
   $output,
   qr/does not have a PRIMARY KEY/,
   "Says that table doesn't have a pk (issue 655)"
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;

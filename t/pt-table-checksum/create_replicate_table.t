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
require "$trunk/bin/pt-table-checksum";

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $source_dbh = $sb->get_dbh_for('source');
my $replica_dbh  = $sb->get_dbh_for('replica1');

if ( !$source_dbh ) {
   plan skip_all => 'Cannot connect to sandbox source';
}
elsif ( !$replica_dbh ) {
   plan skip_all => 'Cannot connect to sandbox replica';
}
else {
   plan tests => 5;
}

# The sandbox servers run with lock_wait_timeout=3 and it's not dynamic
# so we need to specify --set-vars innodb_lock_wait_timeout=3 else the tool will die.
# And --max-load "" prevents waiting for status variables.
my $source_dsn = 'h=127.1,P=12345,u=msandbox,p=msandbox';
my @args       = ($source_dsn, qw(--set-vars innodb_lock_wait_timeout=3), '--max-load', ''); 

my $output;
my $row;

$sb->wipe_clean($source_dbh);
#$sb->create_dbs($source_dbh, [qw(test)]);

# Most other tests implicitly test that --create-replicate-table is on
# by default because they use that functionality.  So here we need to
# test that we can turn it off, that it doesn't blow up if the repl table
# already exists, etc.

eval {
   pt_table_checksum::main(@args, '--no-create-replicate-table');
};
#1
like(
   $EVAL_ERROR,
   qr/--replicate database percona does not exist/,
   "--no-create-replicate-table dies if db doesn't exist"
);

$source_dbh->do('create database percona');
$source_dbh->do('use percona');
eval {
   pt_table_checksum::main(@args, '--no-create-replicate-table');
};
#2
like(
   $EVAL_ERROR,
   qr/--replicate table `percona`.`checksums` does not exist/,
   "--no-create-replicate-table dies if table doesn't exist"
);

my $create_repl_table =
"CREATE TABLE `checksums` (
  db             char(64)     NOT NULL,
  tbl            char(64)     NOT NULL,
  chunk          int          NOT NULL,
  chunk_time     float            NULL,
  chunk_index    varchar(200)     NULL,
  lower_boundary text             NULL,
  upper_boundary text             NULL,
  this_crc       char(40)     NOT NULL,
  this_cnt       int          NOT NULL,
  ${source_name}_crc     char(40)         NULL,
  ${source_name}_cnt     int              NULL,
  ts             timestamp    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (db, tbl, chunk)
) ENGINE=InnoDB;";

$source_dbh->do($create_repl_table);

$output = output(
   sub { pt_table_checksum::main(@args, '--no-create-replicate-table',
      qw(-t sakila.country)) },
);
#3
like(
   $output,
   qr/^\S+\s+0\s+0\s+109\s+0\s+1\s+0\s+\S+\s+sakila.country$/m,
   "Uses pre-created replicate table"
) or diag($output);

# ############################################################################
# Issue 1318: mk-tabke-checksum --create-replicate-table doesn't replicate
# ############################################################################

$sb->wipe_clean($source_dbh);

# Wait until the replica no longer has the percona db.
PerconaTest::wait_until(
   sub {
      eval { $replica_dbh->do("use percona") };
      return 1 if $EVAL_ERROR;
      return 0;
   },
);

pt_table_checksum::main(@args, qw(-t sakila.country --quiet));

# Wait until the repl table replicates, or timeout.
PerconaTest::wait_for_table($replica_dbh, 'percona.checksums');

$row = $replica_dbh->selectrow_arrayref("show tables from percona");
is_deeply(
   $row,
   ['checksums'],
   'Auto-created replicate table replicates (issue 1318)'
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($source_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;

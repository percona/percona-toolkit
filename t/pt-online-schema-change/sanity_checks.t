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
require "$trunk/bin/pt-online-schema-change";

use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

my $dp         = new DSNParser(opts=>$dsn_opts);
my $sb         = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $master_dbh = $sb->get_dbh_for('master');
my $slave_dbh  = $sb->get_dbh_for('slave1');

if ( !$master_dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}

my $q      = new Quoter();
my $tp     = new TableParser(Quoter => $q);
my @args   = qw(--set-vars innodb_lock_wait_timeout=3);
my $output = "";
my $dsn    = "h=127.1,P=12345,u=msandbox,p=msandbox";
my $exit   = 0;
my $sample = "t/pt-online-schema-change/samples";
my $rows;

# #############################################################################
# Checks for the original table (check_orig_table()).
# #############################################################################

# Of course, the orig database and table must exist.
($output, undef) = full_output(
   sub { pt_online_schema_change::main(@args,
         "$dsn,D=nonexistent_db,t=t", qw(--dry-run)) },
);

like( $output,
   qr/Unknown database/,
   "Original database must exist"
);

($output, undef) = full_output(
   sub { pt_online_schema_change::main(@args,
         "$dsn,D=mysql,t=nonexistent_tbl", qw(--dry-run)) },
);

like( $output,
   qr/`mysql`.`nonexistent_tbl` does not exist/,
   "Original table must exist"
);

$sb->load_file('master', "$sample/basic_no_fks_innodb.sql");
$master_dbh->do("USE pt_osc");
$slave_dbh->do("USE pt_osc");

# The orig table cannot have any triggers.
$master_dbh->do("CREATE TRIGGER pt_osc.pt_osc_test AFTER DELETE ON pt_osc.t FOR EACH ROW DELETE FROM pt_osc.t WHERE 0");
($output, undef) = full_output(
   sub { pt_online_schema_change::main(@args,
         "$dsn,D=pt_osc,t=t", qw(--dry-run)) },
);

like( $output,
   qr/`pt_osc`.`t` has triggers/,
   "Original table cannot have triggers"
);
$master_dbh->do('DROP TRIGGER pt_osc.pt_osc_test');

# The new table must have a pk or unique index so the delete trigger is safe.
$master_dbh->do("ALTER TABLE pt_osc.t DROP COLUMN id");
$master_dbh->do("ALTER TABLE pt_osc.t DROP INDEX c");
($output, undef) = full_output(
   sub { pt_online_schema_change::main(@args,
         "$dsn,D=pt_osc,t=t", qw(--dry-run)) },
);

like( $output,
   qr/`pt_osc`.`_t_new` does not have a PRIMARY KEY or a unique index/,
   "New table must have a PK or unique index"
);

# #############################################################################
# Checks for the new table.
# #############################################################################

$sb->load_file('master', "$sample/basic_no_fks_innodb.sql");
$master_dbh->do("USE pt_osc");
$slave_dbh->do("USE pt_osc");

for my $i ( 1..10 ) {
   my $table = ('_' x $i) . 't_new';
   $master_dbh->do("create table $table (id int)");
}

my $x;
($output, $x) = full_output(
   sub { pt_online_schema_change::main(@args,
         "$dsn,D=pt_osc,t=t", qw(--quiet --dry-run)); },
);

like(
   $output,
   qr/Failed to find a unique new table name/,
   "Doesn't try forever to find a new table name"
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;

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
require "$trunk/bin/pt-online-schema-change";

my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
else {
   plan tests => 8;
}

my $vp      = new VersionParser();
my $q       = new Quoter();
my $tp      = new TableParser(Quoter => $q);
my $du      = new MySQLDump();
my $chunker = new TableChunker(Quoter => $q, MySQLDump => $du);
my $o       = new OptionParser();

$o->get_specs("$trunk/bin/pt-online-schema-change");
$o->get_opts();
mk_online_schema_change::__set_quiet(1);

$sb->load_file('master', "t/pt-online-schema-change/samples/small_table.sql");
$dbh->do('use mkosc');

my $old_tbl_struct = $tp->parse($du->get_create_table($dbh, $q, 'mkosc', 'a'));

my %args = (
   dbh           => $dbh,
   db            => 'mkosc',
   tbl           => 'a',
   tmp_tbl       => '__tmp_a',
   old_tbl       => '__old_a',  # what tbl becomes after swapped with tmp_tbl
   VersionParser => $vp,
   Quoter        => $q,
   TableParser   => $tp,
   OptionParser  => $o,
   TableChunker  => $chunker,
   MySQLDump     => $du,
);

my %tbl_info = mk_online_schema_change::check_tables(%args);
is(
   $tbl_info{chunk_column},
   "i",
   "check_tables() returns chunk_column"
);

is(
   $tbl_info{chunk_index},
   "PRIMARY",
   "check_tables() returns chunk_index"
);

ok(
   exists $tbl_info{tbl_struct},
   "check_tables() returns tbl_struct"
);

throws_ok(
   sub { mk_online_schema_change::check_tables(
      %args,
      tbl => 'does_not_exist'
   ) },
   qr/Table mkosc.does_not_exist does not exist/,
   "Table must exist"
);

@ARGV = qw(--rename-tables);
$o->get_opts();
throws_ok(
   sub { mk_online_schema_change::check_tables(
      %args,
      old_tbl => 'a',
   ) },
   qr/Table mkosc.a exists which will prevent mkosc.a/,
   "Old table cannot already exist if --rename-tables"
);

throws_ok(
   sub { mk_online_schema_change::check_tables(
      %args,
      tmp_tbl => 'a',
   ) },
   qr/Temporary table mkosc.a exists/,
   "Temporary table cannot already exist"
);

$dbh->do('CREATE TRIGGER foo AFTER DELETE ON mkosc.a FOR EACH ROW DELETE FROM mkosc.a WHERE 0');
throws_ok(
   sub { mk_online_schema_change::check_tables(%args) },
   qr/Table mkosc.a has triggers/,
   "Old table cannot have triggers"
);
$dbh->do('DROP TRIGGER mkosc.foo');

$dbh->do('ALTER TABLE mkosc.a DROP COLUMN i');
my $tmp_struct = $tp->parse($du->get_create_table($dbh, $q, 'mkosc', 'a'));
throws_ok(
   sub { mk_online_schema_change::check_tables(
      %args,
   ) },
   qr/Table mkosc.a cannot be chunked/,
   "Table must have a chunkable index"
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
exit;

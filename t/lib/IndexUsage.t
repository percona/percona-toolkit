#!/usr/bin/perl

BEGIN {
   die
      "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
}

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More tests => 7;
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

use IndexUsage;
use OptionParser;
use DSNParser;
use Transformers;
use QueryRewriter;
use Sandbox;
use PerconaTest;

use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

Transformers->import(qw(make_checksum));

my $qr  = new QueryRewriter();
my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');

my $iu = new IndexUsage();

# These are mock TableParser::get_keys() structs.
my $actor_idx = {
   PRIMARY             => { name => 'PRIMARY', },
   idx_actor_last_name => { name => 'idx_actor_last_name', }
};
my $film_actor_idx = {
   PRIMARY        => { name => 'PRIMARY', },
   idx_fk_film_id => { name => 'idx_fk_film_id', },
};
my $film_idx = {
   PRIMARY => { name => 'PRIMARY', },
};
my $othertbl_idx = {
   PRIMARY => { name => 'PRIMARY', },
};

# This is more of an integration test than a unit test.
# First we explore all the databases/tables/indexes in the server.
$iu->add_indexes(db=>'sakila', tbl=>'actor',      indexes=>$actor_idx);
$iu->add_indexes(db=>'sakila', tbl=>'film_actor', indexes=>$film_actor_idx );
$iu->add_indexes(db=>'sakila', tbl=>'film',       indexes=>$film_idx );
$iu->add_indexes(db=>'sakila', tbl=>'othertbl',   indexes=>$othertbl_idx);

# Now, we see some queries that use some tables, but not all of them.
$iu->add_table_usage(qw(sakila      actor));
$iu->add_table_usage(qw(sakila film_actor));
$iu->add_table_usage(qw(sakila   othertbl));    # But not sakila.film!

# Some of those queries also use indexes.
$iu->add_index_usage(
   usage      => [
      {  db  => 'sakila',
         tbl => 'film_actor',
         idx => [qw(PRIMARY idx_fk_film_id)],
         alt => [],
      },
      {  db  => 'sakila',
         tbl => 'actor',
         idx => [qw(PRIMARY)],
         alt => [qw(idx_actor_last_name)],
      },
   ],
);

# Now let's find out which indexes were never used.
my @unused;
$iu->find_unused_indexes(
   sub {
      my ($thing) = @_;
      push @unused, $thing;
   }
);

is_deeply(
   \@unused,
   [
      {
         db  => 'sakila',
         tbl => 'actor',
         idx => [ { name=>'idx_actor_last_name', cnt=>0 } ],
      },
      {
         db  => 'sakila',
         tbl => 'othertbl',
         idx => [ { name=>'PRIMARY', cnt=>0 } ],
      },
   ],
   'Got unused indexes for sakila.actor and film_actor',
);

# #############################################################################
# Test save results.
# #############################################################################
SKIP: {
   skip "Cannot connect to sandbox master", 5 unless $dbh;
   skip "Sakila database is not loaded",    5
      unless @{ $dbh->selectall_arrayref("show databases like 'sakila'") };

   # Use mk-index-usage to create all the save results tables.
   # Must --databases foo so it won't find anything, else it will
   # pre-populate the tables with mysql.*, sakila.*, etc.
   `$trunk/bin/pt-index-usage -F /tmp/12345/my.sandbox.cnf --create-save-results-database --save-results-database D=mk_iu --empty-save-results-tables --no-report --quiet --databases foo $trunk/t/lib/samples/empty >/dev/null`;

   $iu = new IndexUsage();

   # #####################################################################
   # First, add all the index, tbl and query data.
   # #####################################################################
   $iu->add_indexes(db=>'sakila', tbl=>'actor',      indexes=>$actor_idx);
   $iu->add_indexes(db=>'sakila', tbl=>'film_actor', indexes=>$film_actor_idx );
   $iu->add_indexes(db=>'sakila', tbl=>'film',       indexes=>$film_idx );
   $iu->add_indexes(db=>'sakila', tbl=>'othertbl',   indexes=>$othertbl_idx);
   
   $iu->add_table_usage(qw(sakila      actor));
   $iu->add_table_usage(qw(sakila film_actor));
   $iu->add_table_usage(qw(sakila   othertbl));    # But not sakila.film!

   my $query       = "select * from sakila.film_actor a "
                   . "left join sakila.actor b using (id)";
   my $fingerprint = $qr->fingerprint($query);
   my $query_id    = make_checksum($fingerprint);
   $iu->add_query(
      query_id    => $query_id,
      fingerprint => $fingerprint,
      sample      => $query,
   );

   $iu->add_index_usage(
      query_id => $query_id,
      usage    => [
         {  db  => 'sakila',
            tbl => 'film_actor',
            idx => [qw(PRIMARY idx_fk_film_id)],
            alt => [],
         },
         {  db  => 'sakila',
            tbl => 'actor',
            idx => [qw(PRIMARY)],
            alt => [qw(idx_actor_last_name)],
         },
      ],
   );

   # #####################################################################
   # Then save it to the database.
   # #####################################################################
   $iu->save_results(
      dbh => $dbh,
      db  => 'mk_iu',
   );

   # #####################################################################
   # Now check if the data was actually and correctly saved.
   # #####################################################################
   my $rows = $dbh->selectall_arrayref("SELECT db,tbl,idx,cnt FROM mk_iu.indexes ORDER BY db,tbl,idx");
   is_deeply(
      $rows,
      [
         ['sakila', 'actor', 'idx_actor_last_name',  '0'],
         ['sakila','actor','PRIMARY','1'],
         ['sakila','film','PRIMARY','0'],
         ['sakila','film_actor','idx_fk_film_id','1'],
         ['sakila','film_actor','PRIMARY','1'],
         ['sakila','othertbl','PRIMARY','0'],
      ],
      "Saves index data"
   ) or print Dumper($rows);

   $rows = $dbh->selectall_arrayref("SELECT db,tbl,cnt FROM mk_iu.tables ORDER BY db,tbl");
   is_deeply(
      $rows,
      [
         [qw(sakila actor      1)],
         [qw(sakila film       0)],
         [qw(sakila film_actor 1)],
         [qw(sakila othertbl   1)],
      ],
      "Saves table data"
   ) or print Dumper($rows);


   $rows = $dbh->selectall_arrayref("select db,tbl,idx,cnt,fingerprint from mk_iu.index_usage left join mk_iu.queries using (query_id) order by db,tbl,idx");
   is_deeply(
      $rows,
      [
         [qw(sakila actor PRIMARY 1), $query],
         [qw(sakila film_actor idx_fk_film_id 1), $query],
         [qw(sakila film_actor PRIMARY 1), $query],
      ],
      "Saves index usage data"
   ) or print Dumper($rows);

   $rows = $dbh->selectall_arrayref("SELECT * FROM mk_iu.index_alternatives ORDER BY db,tbl,idx");
   is_deeply(
      $rows,
      [
         [qw(12852102680195556712 sakila actor PRIMARY idx_actor_last_name 1)],
      ],
      "Save alt index data"
   );

   # #####################################################################
   # Make sure we can find unused indexes.  This doesn't actually use
   # the saved results, but it should work inspite of them.
   # #####################################################################
   @unused = ();
   $iu->find_unused_indexes(
      sub {
         my ($thing) = @_;
         push @unused, $thing;
      }
   );
   is_deeply(
      \@unused,
      [
         {
            db  => 'sakila',
            tbl => 'actor',
            idx => [ { name=>'idx_actor_last_name', cnt=>0 } ],
         },
         {
            db  => 'sakila',
            tbl => 'othertbl',
            idx => [ { name=>'PRIMARY', cnt=>0 } ],
         },
      ],
      'Unused indexes for sakila.actor and film_actor',
   );

   $sb->wipe_clean($dbh);
}

# #############################################################################
# Done.
# #############################################################################
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;

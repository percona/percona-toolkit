#!/usr/bin/perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More tests => 42;

use SchemaIterator;
use FileIterator;
use Quoter;
use DSNParser;
use Sandbox;
use OptionParser;
use TableParser;
use PerconaTest;

use constant PTDEBUG => $ENV{PTDEBUG} || 0;

use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

my $q   = new Quoter();
my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');

my $tp = new TableParser(Quoter => $q);
my $fi = new FileIterator();
my $o  = new OptionParser(description => 'SchemaIterator');
$o->get_specs("$trunk/bin/pt-table-checksum");

my $in  = "$trunk/t/lib/samples/mysqldump-no-data/";
my $out = "t/lib/samples/SchemaIterator/";

sub test_so {
   my ( %args ) = @_;
   my @required_args = qw(test_name result);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless defined $args{$arg};
   }

   @ARGV = $args{filters} ? @{$args{filters}} : ();
   $o->get_opts();

   my $si;
   if ( $args{files} ) {
      my $file_itr = $fi->get_file_itr(@{$args{files}});
      $si = new SchemaIterator(
         file_itr     => $file_itr,
         resume       => $args{resume},
         OptionParser => $o,
         Quoter       => $q,
         TableParser  => $tp,
      );
   }
   else {
      $si = new SchemaIterator(
         dbh          => $dbh,
         resume       => $args{resume},
         OptionParser => $o,
         Quoter       => $q,
         TableParser  => $tp,
      );
   }

   # For result files, each db.tbl is printed on its own line
   # so diff works nicely.
   my $result_file = -f "$trunk/$args{result}";

   my $res = "";
   my @objs;
   eval {
      while ( my $obj = $si->next() ) {
         if ( $args{return_objs} ) {
            push @objs, $obj;
         }
         else {
            if ( $result_file || $args{ddl} ) {
               $res .= "$obj->{db}.$obj->{tbl}\n";
               $res .= "$obj->{ddl}\n\n" if $args{ddl} || $tp;
            }
            else {
               $res .= "$obj->{db}.$obj->{tbl} ";
            }
         }
      }
   };
   
   return \@objs if $args{return_objs};

   if ( $result_file ) {
      my $transform = sub { print sort_query_output(slurp_file(shift)) };
      ok(
         no_diff(
            $res,
            $args{result},
            cmd_output => 1,
            transform_result => $transform,
            transform_sample => $transform,
         ),
         $args{test_name},
      );
   }
   elsif ( $args{like} ) {
      like(
         $res,
         $args{like},
         $args{test_name},
      );
   }
   elsif ( $args{unlike} ) {
      unlike(
         $res,
         $args{unlike},
         $args{test_name},
      );
   }
   elsif ( $args{lives_ok} ) {
      is($EVAL_ERROR, '', $args{test_name});
   }
   else {
      is(
         $res,
         $args{result},
         $args{test_name},
      );
   }

   return;
}

sub sort_query_output {
   my $queries = shift;
   my @queries = split /\n\n/, $queries;
   
   my $sorted;
   for my $query (@queries) {
      $sorted .= join "\n", sort map { my $c = $_; $c =~ s/,$//; $c } split /\n/, $query;
   }
   return $sorted;
}

SKIP: {
   skip "Cannot connect to sandbox master", 22 unless $dbh;
   $sb->wipe_clean($dbh);

   # ########################################################################
   # Test simple, unfiltered get_db_itr().
   # ########################################################################
   test_so(
      result    => "$out/all-dbs-tbls-$sandbox_version.txt",
      test_name => "Iterate all schema objects with dbh",
   );

   # ########################################################################
   # Test filters.
   # ########################################################################
   $sb->load_file('master', "t/lib/samples/SchemaIterator.sql");

   test_so(
      filters   => [qw(-d this_db_does_not_exist)],
      result    => "",
      test_name => "No databases match",
   );

   test_so(
      filters   => [qw(-t this_table_does_not_exist)],
      result    => "",
      test_name => "No tables match",
   );

   # Filter by --databases (-d).
   test_so(
      filters   => [qw(--databases d1)],
      result    => "d1.t1 d1.t2 d1.t3 ",
      test_name => '--databases',
   ); 

   # Filter by --databases (-d) and --tables (-t).
   test_so(
      filters   => [qw(-d d1 -t t2)],
      result    => "d1.t2 ",
      test_name => '--databases and --tables',
   );

   # Ignore some dbs and tbls.
   test_so(
      filters   => ['--ignore-databases', 'mysql,sakila,d1,d3,percona_test'],
      result    => "d2.t1 ",
      test_name => '--ignore-databases',
   );

   test_so(
      filters   => ['--ignore-databases', 'mysql,sakila,d2,d3,percona_test',
                    '--ignore-tables', 't1,t2'],
      result    => "d1.t3 ",
      test_name => '--ignore-databases and --ignore-tables',
   );
  
   # Select some dbs but ignore some tables.
   test_so(
      filters   => ['-d', 'd1', '--ignore-tables', 't1,t3'],
      result    => "d1.t2 ",
      test_name => '--databases and --ignore-tables',
   );

   # Filter by engines.  This also tests that --engines is case-insensitive
   test_so(
      filters   => ['-d', 'd1,d2,d3', '--engines', 'INNODB'],
      result    => ($sandbox_version ge '5.5' ? 'd1.t2 d2.t1 ' : "d1.t2 "),
      test_name => '--engines',
   );

   test_so(
      filters   => ['-d', 'd1,d2,d3', '--ignore-engines', 'innodb,myisam'],
      result    => "d1.t3 ",
      test_name => '--ignore-engines',
   );
   
   # Filter by regex.
   test_so(
      filters   => ['--databases-regex', 'd[13]', '--tables-regex', 't[^3]'],
      result    => "d1.t1 d1.t2 ",
      test_name => '--databases-regex and --tables-regex',
   );

   test_so(
      filters   => ['--ignore-databases-regex', '(?:^d[23]|mysql|info|sakila|percona_test)',
                    '--ignore-tables-regex', 't[^23]'],
      result    => "d1.t2 d1.t3 ",
      test_name => '--ignore-databases-regex',
   );

   # ########################################################################
   # Filter views.
   # ########################################################################
   SKIP: {
      skip 'Sandbox master does not have the sakila database', 1
         unless @{$dbh->selectcol_arrayref("SHOW DATABASES LIKE 'sakila'")};

      test_so(
         filters   => [qw(-d sakila)],
         result    => "",  # hack; uses unlike instead
         unlike    => qr/
             actor_info
            |customer_list
            |film_list
            |nicer_but_slower_film_list
            |sales_by_film_category
            |sales_by_store
            |staff_list/x,
         test_name => "Iterator does not return views",
      );
   };

   # ########################################################################
   # Issue 806: mk-table-sync --tables does not honor schema qualier
   # ########################################################################
   # Filter by db-qualified table.  There is t1 in both d1 and d2.
   # We want only d1.t1.
   test_so(
      filters   => [qw(-t d1.t1)],
      result    => "d1.t1 ",
      test_name => '-t d1.t1 (issue 806)',
   );

   test_so(
      filters   => [qw(-d d1 -t d1.t1)],
      result    => "d1.t1 ",
      test_name => '-d d1 -t d1.t1 (issue 806)',
   );

   test_so(
      filters   => [qw(-d d2 -t d1.t1)],
      result    => "",
      test_name => '-d d2 -t d1.t1 (issue 806)',
   );

   test_so(
      filters   => ['-t','d1.t1,d1.t3'],
      result    => "d1.t1 d1.t3 ",
      test_name => '-t d1.t1,d1.t3 (issue 806)',
   );

   test_so(
      filters   => ['--ignore-databases', 'mysql,sakila,percona_test',
                    '--ignore-tables', 'd1.t1'],
      result    => "d1.t2 d1.t3 d2.t1 ",
      test_name => '--ignore-databases and --ignore-tables d1.t1 (issue 806)',
   );

   test_so(
      filters   => ['-t','d1.t3,d2.t1'],
      result    => "d1.t3 d2.t1 ",
      test_name => '-t d1.t3,d2.t1 (issue 806)',
   );

   # ########################################################################
   # Issue 1161: make_filter() with only --tables db.foo filter does not work
   # ########################################################################
   # mk-index-usage does not have any of the schema filters with default
   # values like --engines so when we do --tables that will be the only
   # filter.
   $o = new OptionParser(description => 'SchemaIterator');
   $o->get_specs("$trunk/bin/pt-index-usage");

   test_so(
      filters   => [qw(-t d1.t1)],
      result    => "d1.t1 ",
      test_name => '-t d1.t1 (issue 1161)',
   );

   # ########################################################################
   # Issue 1193: Make SchemaIterator skip PERFORMANCE_SCHEMA
   # ########################################################################
   SKIP: {
      skip "Test for MySQL v5.5", 1 unless $sandbox_version ge '5.5';

      test_so(
         result    => "", # hack, uses unlike instead
         unlike    => qr/^performance_schema/,
         test_name => "performance_schema automatically ignored",
      );
   }

   # ########################################################################
   # Getting CREATE TALBE (ddl).
   # ########################################################################
   test_so(
      filters   => [qw(-t mysql.user)],
      result    => "$out/mysql-user-ddl-$sandbox_version.txt",
      test_name => "Get CREATE TABLE with dbh",
   );

   $sb->wipe_clean($dbh);
};

# ############################################################################
# Test getting schema from mysqldump files.
# ############################################################################

test_so(
   files     => ["$in/dump001.txt"],
   result    => "test.a test.b test2.a ",
   test_name => "Iterate schema in dump001.txt",
);

test_so(
   files     => ["$in/all-dbs.txt"],
   result    => "$out/all-dbs.txt",
   ddl       => 1,
   test_name => "Iterate schema in all-dbs.txt",
);

test_so(
   files     => ["$in/dump001.txt", "$in/dump001.txt"],
   result    => "$out/multiple-files.txt",
   ddl       => 1,
   test_name => "Iterate schema in multiple files",
);

test_so(
   files     => ["$in/dump001.txt"],
   filters   => [qw(--databases TEST2)],
   result    => "$out/all-dbs-dump001.txt",
   test_name => "Filter dump file by --databases",
);

# ############################################################################
# Getting tbl_struct.
# ############################################################################
my $objs = test_so(
   files     => ["$in/dump001.txt"],
   result      => "",  # hack to let return_objs work
   test_name   => "",  # hack to let return_objs work
   return_objs => 1,
);

my $n_tbl_structs = grep { exists $_->{tbl_struct} } @$objs;

is(
   $n_tbl_structs,
   scalar @$objs,
   'Got tbl_struct for each schema object'
);

# ############################################################################
# Resume
# ############################################################################
test_so(
   filters   => [qw(-d sakila)],
   result    => $sandbox_version ge '5.1'
                ? "$out/resume-from-sakila-payment.txt"
                : "$out/resume-from-sakila-payment-5.0.txt",
   resume    => 'sakila.payment',
   test_name => "Resume"
);

# Ignore the table being resumed from; resume from next table.
test_so(
   filters   => [qw(-d sakila --ignore-tables sakila.payment)],
   result    => $sandbox_version ge '5.1'
                ? "$out/resume-from-ignored-sakila-payment.txt"
                : "$out/resume-from-ignored-sakila-payment-5.0.txt",
   resume    => 'sakila.payment',
   test_name => "Resume from ignored table"
);

# ############################################################################
# pt-table-checksum v2 fails when --resume + --ignore-database is used
# https://bugs.launchpad.net/percona-toolkit/+bug/911385
# ############################################################################

test_so(
   filters   => ['--ignore-databases', 'sakila,mysql'],
   result    => "",
   lives_ok  => 1,
   resume    => 'sakila.payment',
   test_name => "Bug 911385: ptc works with --resume + --ignore-database"
);

$dbh->do("CREATE DATABASE zakila");
$dbh->do("CREATE TABLE zakila.bug_911385 (i int)");
test_so(
   filters   => ['--ignore-databases', 'sakila,mysql'],
   result    => "zakila.bug_911385 ",
   resume    => 'sakila.payment',
   test_name => "Bug 911385: ...and continues to the next db"
);
$dbh->do("DROP DATABASE zakila");

test_so(
   filters   => [qw(--ignore-tables-regex payment --ignore-databases mysql)],
   result    => "",
   lives_ok  => 1,
   resume    => 'sakila.payment',
   test_name => "Bug 911385: ptc works with --resume + --ignore-tables-regex"
);

test_so(
   filters   => [qw(--ignore-tables-regex payment --ignore-databases mysql)],
   result    => "sakila.rental sakila.staff sakila.store ",
   resume    => 'sakila.payment',
   test_name => "Bug 911385: ...and continues to the next table"
);

# #############################################################################
# Bug 1047335: pt-duplicate-key-checker fails when it encounters a crashed table
# https://bugs.launchpad.net/percona-toolkit/+bug/1047335
# #############################################################################

my $master3_port   = 2900;
my $master_basedir = "/tmp/$master3_port";
diag(`$trunk/sandbox/stop-sandbox $master3_port >/dev/null`);
diag(`$trunk/sandbox/start-sandbox master $master3_port >/dev/null`);
my $dbh3 = $sb->get_dbh_for("master3");

SKIP: {
   skip "No /dev/urandom, can't corrupt the database", 1
      unless -e q{/dev/urandom};

   $sb->load_file('master3', "t/lib/samples/bug_1047335_crashed_table.sql");

   # Create the SI object before crashing the table
   my $tmp_si = new SchemaIterator(
            dbh          => $dbh3,
            OptionParser => $o,
            Quoter       => $q,
            TableParser  => $tp,
            # This is needed because the way we corrupt tables
            # accidentally removes the database from SHOW DATABASES
            db           => 'bug_1047335',
         );

   my $db_dir = "$master_basedir/data/bug_1047335";
   my $myi    = glob("$db_dir/crashed_table.[Mm][Yy][Iy]");
   my $frm    = glob("$db_dir/crashed_table.[Ff][Rr][Mm]");

   die "Cannot find .myi file for crashed_table" unless $myi && -f $myi;

   # Truncate the .myi file to corrupt it
   truncate($myi, 4096);

   use File::Slurp qw( write_file );

   # Corrupt the .frm file
   open my $urand_fh, q{<}, "/dev/urandom"
      or die "Cannot open /dev/urandom";
   write_file($frm, scalar(<$urand_fh>), slurp_file($frm), scalar(<$urand_fh>));
   close $urand_fh;

   $dbh3->do("FLUSH TABLES");
   eval { $dbh3->do("SELECT etc FROM bug_1047335.crashed_table WHERE etc LIKE '10001' ORDER BY id ASC LIMIT 1") };

   my $w = '';
   {
      local $SIG{__WARN__} = sub { $w .= shift };
      1 while $tmp_si->next();
   }

   like(
      $w,
      qr/bug_1047335.crashed_table because SHOW CREATE TABLE failed:/,
      "->next() gives a warning if ->get_create_table dies from a strange error",
   );

}

$dbh3->do(q{DROP DATABASE IF EXISTS bug_1047335_2});
$dbh3->do(q{CREATE DATABASE bug_1047335_2});

my $broken_frm = "$trunk/t/lib/samples/broken_tbl.frm";
my $db_dir_2   = "$master_basedir/data/bug_1047335_2";

diag(`cp $broken_frm $db_dir_2 2>&1`);

$dbh3->do("FLUSH TABLES");

my $tmp_si2 = new SchemaIterator(
         dbh          => $dbh3,
         OptionParser => $o,
         Quoter       => $q,
         TableParser  => $tp,
         # This is needed because the way we corrupt tables
         # accidentally removes the database from SHOW DATABASES
         db           => 'bug_1047335_2',
      );

my $w = '';
{
   local $SIG{__WARN__} = sub { $w .= shift };
   1 while $tmp_si2->next();
}

like(
   $w,
   qr/\QSkipping bug_1047335_2.broken_tbl because SHOW CREATE TABLE failed:/,
   "...same as above, but using t/lib/samples/broken_tbl.frm",
);

# This might fail. Doesn't matter -- stop_sandbox will just rm -rf the folder
eval {
   $dbh3->do("DROP DATABASE IF EXISTS bug_1047335");
   $dbh3->do("DROP DATABASE IF EXISTS bug_1047335_2");
};

diag(`$trunk/sandbox/stop-sandbox $master3_port >/dev/null`);

# #############################################################################
# Bug 1136559: Deep recursion on subroutine "SchemaIterator::_iterate_dbh"
# #############################################################################

$sb->wipe_clean($dbh);
diag(`/tmp/12345/use < $trunk/t/lib/samples/100-dbs.sql`);

test_so(
   filters   => [],
   result    => "foo001.bar001 ",
   lives_ok  => 1,
   test_name => "Bug 1136559: Deep recursion on subroutine SchemaIterator::_iterate_dbh",
);

diag(`/tmp/12345/use < $trunk/t/lib/samples/100-dbs-drop.sql`);


# #############################################################################
# https://bugs.launchpad.net/percona-toolkit/+bug/1304062 
# #############################################################################

$sb->load_file('master', "t/lib/samples/SchemaIterator.sql");
$dbh->do("CREATE TABLE d3.t1 (id int auto_increment primary key, c  char(8))");

test_so(
   filters   => ['--ignore-tables', 'd1.t1,d2.t1'],
   like    => qr/^d1.t2 d1.t3 d3.t1 mysql/,
   result => "",
   test_name => '--ignore-tables (bug 1304062)',
);

my $si = new SchemaIterator(
   dbh          => $dbh,
   OptionParser => $o,
   Quoter       => $q,
   TableParser  => $tp,
);
for my $db (qw( information_schema performance_schema lost+found percona_schema )) {
   is(
      $si->database_is_allowed($db),
      0,
      "database is allowed: $db",
   );
}

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);  
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
exit;

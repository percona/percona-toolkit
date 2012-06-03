#!/usr/bin/perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More tests => 32;

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

my $tp;
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
         keep_ddl     => defined $args{keep_ddl} ? $args{keep_ddl} : 1,
         resume       => $args{resume},
         OptionParser => $o,
         Quoter       => $q,
         TableParser  => $tp,
      );
   }
   else {
      $si = new SchemaIterator(
         dbh          => $dbh,
         keep_ddl     => defined $args{keep_ddl} ? $args{keep_ddl} : 1,
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

   return \@objs if $args{return_objs};

   if ( $result_file ) {
      ok(
         no_diff(
            $res,
            $args{result},
            cmd_output    => 1,
         ),
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
   else {
      is(
         $res,
         $args{result},
         $args{test_name},
      );
   }

   return;
}

SKIP: {
   skip "Cannot connect to sandbox master", 22 unless $dbh;
   $sb->wipe_clean($dbh);

   # ########################################################################
   # Test simple, unfiltered get_db_itr().
   # ########################################################################
   test_so(
      result    => $sandbox_version eq '5.1' ? "$out/all-dbs-tbls.txt"
                                             : "$out/all-dbs-tbls-5.0.txt",
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
      filters   => ['--ignore-databases', 'mysql,sakila,d1,d3'],
      result    => "d2.t1 ",
      test_name => '--ignore-databases',
   );

   test_so(
      filters   => ['--ignore-databases', 'mysql,sakila,d2,d3',
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
      result    => "d1.t2 ",
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
      filters   => ['--ignore-databases-regex', '(?:^d[23]|mysql|info|sakila)',
                    '--ignore-tables-regex', 't[^23]'],
      result    => "d1.t2 d1.t3 ",
      test_name => '--ignore-databases-regex',
   );

   # ########################################################################
   # Filter views.
   # ########################################################################
   SKIP: {
      skip 'Sandbox master does not have the sakila database', 1
         unless @{$dbh->selectcol_arrayref('SHOW DATABASES LIKE "sakila"')};

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
      filters   => ['--ignore-databases', 'mysql,sakila',
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
   $tp = new TableParser(Quoter => $q);
   test_so(
      filters   => [qw(-t mysql.user)],
      result    => $sandbox_version eq '5.1' ? "$out/mysql-user-ddl.txt"
                                             : "$out/mysql-user-ddl-5.0.txt",
      test_name => "Get CREATE TABLE with dbh",
   );

   # Kill the TableParser obj in case the next tests don't want to use it.
   $tp = undef;

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
   result    => "$out/dump001-twice.txt",
   ddl       => 1,
   test_name => "Iterate schema in multiple files",
);

test_so(
   files     => ["$in/dump001.txt"],
   filters   => [qw(--databases TEST2)],
   result    => "test2.a ",
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
   0,
   'No tbl_struct without TableParser'
);

$tp = new TableParser(Quoter => $q);

$objs = test_so(
   files     => ["$in/dump001.txt"],
   result      => "",  # hack to let return_objs work
   test_name   => "",  # hack to let return_objs work
   return_objs => 1,
);

$n_tbl_structs = grep { exists $_->{tbl_struct} } @$objs;

is(
   $n_tbl_structs,
   scalar @$objs,
   'Got tbl_struct for each schema object'
);

# Kill the TableParser obj in case the next tests don't want to use it.
$tp = undef;

# ############################################################################
# keep_ddl
# ############################################################################
$objs = test_so(
   files       => ["$in/dump001.txt"],
   result      => "",  # hack to let return_objs work
   test_name   => "",  # hack to let return_objs work
   return_objs => 1,
   keep_ddl    => 0,
);

my $n_ddls = grep { exists $_->{ddl} } @$objs;

is(
   $n_ddls,
   0,
   'DDL deleted unless keep_ddl'
);

# ############################################################################
# Resume
# ############################################################################
test_so(
   filters   => [qw(-d sakila)],
   result    => "$out/resume-from-sakila-payment.txt",
   resume    => 'sakila.payment',
   test_name => "Resume"
);

# Ignore the table being resumed from; resume from next table.
test_so(
   filters   => [qw(-d sakila --ignore-tables sakila.payment)],
   result    => "$out/resume-from-ignored-sakila-payment.txt",
   resume    => 'sakila.payment',
   test_name => "Resume from ignored table"
);

# #############################################################################
# Done.
# #############################################################################
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;

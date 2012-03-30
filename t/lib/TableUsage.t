#!/usr/bin/perl

BEGIN {
   die "The MAATKIT_WORKING_COPY environment variable is not set.  See http://code.google.com/p/maatkit/wiki/Testing"
      unless $ENV{MAATKIT_WORKING_COPY} && -d $ENV{MAATKIT_WORKING_COPY};
   unshift @INC, "$ENV{MAATKIT_WORKING_COPY}/common";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More tests => 34;

use MaatkitTest;
use QueryParser;
use SQLParser;
use TableUsage;
use Sandbox;

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');

use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

my $qp = new QueryParser();
my $sp = new SQLParser();
my $ta = new TableUsage(QueryParser => $qp, SQLParser => $sp);
isa_ok($ta, 'TableUsage');

sub test_get_table_usage {
   my ( $query, $cats, $desc ) = @_;
   my $got = $ta->get_table_usage(query=>$query);
   is_deeply(
      $got,
      $cats,
      $desc,
   ) or print Dumper($got);
   return;
}

# ############################################################################
# Queries parsable by SQLParser: SELECT, INSERT, UPDATE and DELETE
# ############################################################################
test_get_table_usage(
   "SELECT * FROM d.t WHERE id>100",
   [
      [
         { context => 'SELECT',
           table   => 'd.t',
         },
         { context => 'WHERE',
           table   => 'd.t',
         },
      ],
   ],
   "SELECT FROM one table"
); 

test_get_table_usage(
   "SELECT t1.* FROM d.t1 LEFT JOIN d.t2 USING (id) WHERE d.t2.foo IS NULL",
   [
      [
         { context => 'SELECT',
           table   => 'd.t1',
         },
         { context => 'JOIN',
           table   => 'd.t1',
         },
         { context => 'JOIN',
           table   => 'd.t2',
         },
         { context => 'WHERE',
           table   => 'd.t2',
         },
      ],
   ],
   "SELECT JOIN two tables"
); 

test_get_table_usage(
   "DELETE FROM d.t WHERE type != 'D' OR type IS NULL",
   [
      [
         { context => 'DELETE',
           table   => 'd.t',
         },
         { context => 'WHERE',
           table   => 'd.t',
         },
      ],
   ],
   "DELETE one table"
); 

test_get_table_usage(
   "INSERT INTO d.t (col1, col2) VALUES ('a', 'b')",
   [
      [
         { context => 'INSERT',
           table   => 'd.t',
         },
         { context => 'SELECT',
           table   => 'DUAL',
         },
      ],
   ],
   "INSERT VALUES, no SELECT"
); 

test_get_table_usage(
   "INSERT INTO d.t SET col1='a', col2='b'",
   [
      [
         { context => 'INSERT',
           table   => 'd.t',
         },
         { context => 'SELECT',
           table   => 'DUAL',
         },
      ],
   ],
   "INSERT SET, no SELECT"
); 

test_get_table_usage(
   "UPDATE d.t SET foo='bar' WHERE foo IS NULL",
   [
      [
         { context => 'UPDATE',
           table   => 'd.t',
         },
         { context => 'SELECT',
           table   => 'DUAL',
         },
         { context => 'WHERE',
           table   => 'd.t',
         },
      ],
   ],
   "UPDATE one table"
); 

test_get_table_usage(
   "SELECT * FROM zn.edp
      INNER JOIN zn.edp_input_key edpik     ON edp.id = edpik.id
      INNER JOIN `zn`.`key`       input_key ON edpik.input_key = input_key.id
      WHERE edp.id = 296",
   [
      [
         { context => 'SELECT',
           table   => 'zn.edp',
         },
         { context => 'SELECT',
           table   => 'zn.edp_input_key',
         },
         { context => 'SELECT',
           table   => 'zn.key',
         },
         { context => 'JOIN',
           table   => 'zn.edp',
         },
         { context => 'JOIN',
           table   => 'zn.edp_input_key',
         },
         { context => 'JOIN',
           table   => 'zn.key',
         },
         { context => 'WHERE',
           table   => 'zn.edp',
         },
      ],
   ],
   "SELECT with 2 JOIN and WHERE"
);

test_get_table_usage(
   "REPLACE INTO db.tblA (dt, ncpc)
      SELECT dates.dt, scraped.total_r
        FROM tblB          AS dates
        LEFT JOIN dbF.tblC AS scraped
          ON dates.dt = scraped.dt AND dates.version = scraped.version",
   [
      [
         { context => 'REPLACE',
           table   => 'db.tblA',
         },
         { context => 'SELECT',
           table   => 'tblB',
         },
         { context => 'SELECT',
           table   => 'dbF.tblC',
         },
         { context => 'JOIN',
           table   => 'tblB',
         },
         { context => 'JOIN',
           table   => 'dbF.tblC',
         },
      ],
   ],
   "REPLACE SELECT JOIN"
);

test_get_table_usage(
   'UPDATE t1 AS a JOIN t2 AS b USING (id) SET a.foo="bar" WHERE b.foo IS NOT NULL',
   [
      [
         { context => 'UPDATE',
           table   => 't1',
         },
         { context => 'SELECT',
           table   => 'DUAL',
         },
         { context => 'JOIN',
           table   => 't1',
         },
         { context => 'JOIN',
           table   => 't2',
         },
         { context => 'WHERE',
           table   => 't2',
         },
      ],
   ],
   "UPDATE joins 2 tables, writes to 1, filters by 1"
);

test_get_table_usage(
   'UPDATE t1 INNER JOIN t2 USING (id) SET t1.foo="bar" WHERE t1.id>100 AND t2.id>200',
   [
      [
         { context => 'UPDATE',
           table   => 't1',
         },
         { context => 'SELECT',
           table   => 'DUAL',
         },
         { context => 'JOIN',
           table   => 't1',
         },
         { context => 'JOIN',
           table   => 't2',
         },
         { context => 'WHERE',
           table   => 't1',
         },
         { context => 'WHERE',
           table   => 't2',
         },
      ],
   ],
   "UPDATE joins 2 tables, writes to 1, filters by 2"
);

test_get_table_usage(
   'UPDATE t1 AS a JOIN t2 AS b USING (id) SET a.foo="bar", b.foo="bat" WHERE a.id=1',
   [
      [
         { context => 'UPDATE',
           table   => 't1',
         },
         { context => 'SELECT',
           table   => 'DUAL',
         },
         { context => 'JOIN',
           table   => 't1',
         },
         { context => 'JOIN',
           table   => 't2',
         },
         { context => 'WHERE',
           table   => 't1',
         },
      ],
      [
         { context => 'UPDATE',
           table   => 't2',
         },
         { context => 'SELECT',
           table   => 'DUAL',
         },
         { context => 'JOIN',
           table   => 't1',
         },
         { context => 'JOIN',
           table   => 't2',
         },
         { context => 'WHERE',
           table   => 't1',
         },
      ],
   ],
   "UPDATE joins 2 tables, writes to 2, filters by 1"
);

test_get_table_usage(
   'insert into t1 (a, b, c) select x, y, z from t2 where x is not null',
   [
      [
         { context => 'INSERT',
           table   => 't1',
         },
         { context => 'SELECT',
           table   => 't2',
         },
         { context => 'WHERE',
           table   => 't2',
         },
      ],
   ],
   "INSERT INTO t1 SELECT FROM t2",
);

test_get_table_usage(
   'insert into t (a, b, c) select a.x, a.y, b.z from a, b where a.id=b.id',
   [
      [
         { context => 'INSERT',
           table   => 't',
         },
         { context => 'SELECT',
           table   => 'a',
         },
         { context => 'SELECT',
           table   => 'b',
         },
         { context => 'JOIN',
           table   => 'a',
         },
         { context => 'JOIN',
            table  => 'b',
         },
      ],
   ],
   "INSERT INTO t SELECT FROM a, b"
);

test_get_table_usage(
   'INSERT INTO bar
      SELECT edpik.* 
         FROM zn.edp 
            INNER JOIN zn.edp_input_key AS edpik ON edpik.id = edp.id 
            INNER JOIN `zn`.`key` input_key 
            INNER JOIN foo
         WHERE edp.id = 296
            AND edpik.input_key = input_key.id',
   [
      [
         { context => 'INSERT',
           table   => 'bar',
         },
         { context => 'SELECT',
           table   => 'zn.edp_input_key',
         },
         { context => 'JOIN',
           table   => 'zn.edp',
         },
         { context => 'JOIN',
           table   => 'zn.edp_input_key',
         },
         { context => 'JOIN',
           table   => 'zn.key',
         },
         { context => 'TLIST',
           table   => 'foo',
         },
         { context => 'WHERE',
           table   => 'zn.edp',
         },

      ],
   ],
   "INSERT SELECT with TLIST table"
);

test_get_table_usage(
   "select country.country, city.city from city join country using (country_id) where country = 'Brazil' and city like 'A%' limit 1",
   [
      [
         { context => 'SELECT',
           table   => 'country',
         },
         { context => 'SELECT',
           table   => 'city',
         },
         { context => 'JOIN',
           table   => 'city',
         },
         { context => 'JOIN',
           table   => 'country',
         },
      ],
   ],
   "Unresolvable tables in WHERE"
);

test_get_table_usage(
   "select c from t where 1",
   [
      [
         { context => 'SELECT',
           table   => 't',
         },
         { context => 'WHERE',
           table   => 'DUAL',
         },
      ],
   ],
   "WHERE <constant>"
);

test_get_table_usage(
   "select c from t where 1=1",
   [
      [
         { context => 'SELECT',
           table   => 't',
         },
         { context => 'WHERE',
           table   => 'DUAL',
         },
      ],
   ],
   "WHERE <constant>=<constant>"
);

test_get_table_usage(
   "select now()",
   [
      [
         { context => 'SELECT',
           table   => 'DUAL',
         },
      ],
   ],
   "SELECT NOW()"
);

#test_get_table_usage(
#   "SELECT
#      automated_process.id id,
#      class,
#      automated_process_instance.server,
#      IF(start IS NULL, 0, 1),
#      owner
#   FROM
#      zn.automated_process_instance      
#      INNER JOIN zn.automated_process ON automated_process=automated_process.id
#   WHERE
#      automated_process_instance.id = 5251414",
#   [
#      [
#         { context => 'SELECT',
#           table   => 'zn.automated_process',
#         },
#         { context => 'SELECT',
#           table   => 'zn.automated_process_instance',
#         },
#         { context => 'JOIN',
#           table   => 'zn.automated_process_instance',
#         },
#         { context => 'JOIN',
#           table   => 'zn.automated_process',
#         },
#         { context => 'WHERE',
#           table   => 'zn.automated_process_instance',
#         },
#      ]
#   ],
#   "SELECT explicit INNER JOIN with condition"
#);

# ############################################################################
# Queries parsable by QueryParser
# ############################################################################
test_get_table_usage(
   "ALTER TABLE tt.ks ADD PRIMARY KEY(`d`,`v`)",
   [
      [
         { context => 'ALTER',
           table   => 'tt.ks',
         },
      ],
   ],
   "ALTER TABLE"
);

test_get_table_usage(
   "DROP TABLE foo",
   [
      [
         { context => 'DROP_TABLE',
           table   => 'foo',
         },
      ],
   ],
   "DROP TABLE"
);

test_get_table_usage(
   "DROP TABLE IF EXISTS foo",
   [
      [
         { context => 'DROP_TABLE',
           table   => 'foo',
         },
      ],
   ],
   "DROP TABLE IF EXISTS"
);

# #############################################################################
# Change DUAL to something else.
# #############################################################################
$ta = new TableUsage(
   QueryParser => $qp,
   SQLParser   => $sp,
   constant_data_value => '<const>',
);

test_get_table_usage(
   "INSERT INTO d.t (col1, col2) VALUES ('a', 'b')",
   [
      [
         { context => 'INSERT',
           table   => 'd.t',
         },
         { context => 'SELECT',
           table   => '<const>',
         },
      ],
   ],
   "Change constant_data_value"
); 

# Restore original TableUsage obj for other tests.
$ta = new TableUsage(
   QueryParser => $qp,
   SQLParser   => $sp,
);


# ###########################################################################
# CREATE
# ###########################################################################

test_get_table_usage(
   "CREATE TABLE db.tbl (id INT) ENGINE=InnoDB",
   [
      [
         { context => 'CREATE',
           table   => 'db.tbl',
         },
      ],
   ],
   "CREATE TABLE",
); 

test_get_table_usage(
   "CREATE TABLE db.tbl SELECT city_id FROM sakila.city WHERE city_id>100",
   [
      [
         { context => 'CREATE',
           table   => 'db.tbl',
         },
         { context => 'SELECT',
           table   => 'sakila.city',
         },
         { context => 'WHERE',
           table   => 'sakila.city',
         },
      ],
   ],
   "CREATE..SELECT"
); 

# ############################################################################
# Use Schema instead of EXPLAIN EXTENDED.
# ############################################################################
use OptionParser;
use DSNParser;
use Quoter;
use TableParser;
use FileIterator;
use Schema;
use SchemaIterator;

my $o  = new OptionParser(description => 'SchemaIterator');
$o->get_specs("$trunk/mk-table-checksum/mk-table-checksum");

my $q          = new Quoter;
my $tp         = new TableParser(Quoter => $q);
my $fi         = new FileIterator();
my $file_itr   = $fi->get_file_itr("$trunk/common/t/samples/mysqldump-no-data/dump001.txt");
my $schema     = new Schema();
my $schema_itr = new SchemaIterator(
   file_itr     => $file_itr,
   OptionParser => $o,
   Quoter       => $q,
   TableParser  => $tp,
   keep_ddl     => 1,
   Schema       => $schema,
);
# Init schema.
1 while ($schema_itr->next_schema_object());

# Before, this is as correct as we can determine.  The WHERE access is missing
# because c3 is not qualified and there's multiple tables, so the code can't
# figure out to which table it belongs.
test_get_table_usage(
   "SELECT a.c1, c3 FROM a JOIN b ON a.c2=c3 WHERE NOW()<c3",
   [
      [
         { context => 'SELECT',
           table   => 'a',
         },
         { context => 'JOIN',
           table   => 'a',
         },
         { context => 'JOIN',
           table   => 'b',
         },
      ],
   ],
   "Tables without Schema"
); 

# After, now we have a db for table b, but not for a because the schema
# we loaded has two table a (test.a and test2.a).  The WHERE access is
# now present.
$sp->set_Schema($schema);
test_get_table_usage(
   "SELECT a.c1, c3 FROM a JOIN b ON a.c2=c3 WHERE NOW()<c3",
   [
      [
         { context => 'SELECT',
           table   => 'a',
         },
         { context => 'SELECT',
           table   => 'test.b',
         },
         { context => 'JOIN',
           table   => 'a',
         },
         { context => 'JOIN',
           table   => 'test.b',
         },
         { context => 'WHERE',
           table   => 'test.b',
         },
      ],
   ],
   "Tables with Schema"
); 

# Set it back for the next tests.
$sp->set_Schema(undef);

# #############################################################################
# Use a dbh for EXPLAIN EXTENDED.
# #############################################################################
SKIP: {
   skip 'Cannot connect to sandbox master', 1 unless $dbh;
   

   $ta = new TableUsage(
      QueryParser => $qp,
      SQLParser   => $sp,
      dbh         => $dbh,
   );

   # Compare this with the same query/test after USE sakila.
   test_get_table_usage(
      "select city_id, country.country_id from city, country where city_id>100 or country='Brazil' limit 1",
      [
         [
            { context => 'SELECT',
              table => 'country'
            },
            { context => 'TLIST',
              table => 'city'
            },
            { context => 'TLIST',
              table => 'country'
            },
         ]
      ],
      "Ambiguous tables"
   );
   
   is_deeply(
      $ta->errors(),
      [ 'NO_DB_SELECTED' ],
      'NO_DB_SELECTED error'
   );

   $dbh->do('USE sakila');

   test_get_table_usage(
      "select city_id, country.country_id from city, country where city_id>100 or country='Brazil' limit 1",
      [
         [ { context => 'SELECT',
             table   => 'sakila.city'
            },
            { context => 'SELECT',
              table   => 'sakila.country'
            },
            { context => 'TLIST',
              table   => 'sakila.city'
            },
            { context => 'TLIST',
              table   => 'sakila.country'
            },
            { context => 'WHERE',
              table   => 'sakila.city'
            },
            { context => 'WHERE',
              table   => 'sakila.country'
            }
         ],
      ],
      "Disambiguate WHERE columns"
   );

   test_get_table_usage(
      "select city_id, country from city, country where city.city_id>100 or country.country='China' limit 1",
      [
         [ { context => 'SELECT',
             table   => 'sakila.city'
            },
            { context => 'SELECT',
              table   => 'sakila.country'
            },
            { context => 'TLIST',
              table   => 'sakila.city'
            },
            { context => 'TLIST',
              table   => 'sakila.country'
            },
            { context => 'WHERE',
              table   => 'sakila.city'
            },
            { context => 'WHERE',
              table   => 'sakila.country'
            }
         ],
      ],
      "Disambiguate CLIST columns"
   );

   test_get_table_usage(
      "select city.city, country.country from city join country on city=country where city.city_id>100 or country.country='China' limit 1",
      [
         [ { context => 'SELECT',
             table   => 'sakila.city'
            },
            { context => 'SELECT',
              table   => 'sakila.country'
            },
            { context => 'JOIN',
              table   => 'sakila.city'
            },
            { context => 'JOIN',
              table   => 'sakila.country'
            },
            { context => 'WHERE',
              table   => 'sakila.city'
            },
            { context => 'WHERE',
              table   => 'sakila.country'
            }
         ],
      ],
      "Disambiguate JOIN columns"
   );

   test_get_table_usage(
      "SELECT COUNT(*), MAX(country_id), MIN(country_id) FROM sakila.city A JOIN sakila.country B USING (country_id) WHERE B.country = 'Brazil'",
      [
         [
            { context => 'SELECT',
              table   => 'sakila.city',
            },
            { context => 'JOIN',
              table => 'sakila.city',
            },
            { context => 'JOIN',
              table => 'sakila.country',
            },
            { context => 'WHERE',
              table => 'sakila.country',
            },
         ],
      ],
      "SELECT with multiple CLIST functions"
   );
}

# #############################################################################
# Done.
# #############################################################################
my $output = '';
{
   local *STDERR;
   open STDERR, '>', \$output;
   $ta->_d('Complete test coverage');
}
like(
   $output,
   qr/Complete test coverage/,
   '_d() works'
);
exit;

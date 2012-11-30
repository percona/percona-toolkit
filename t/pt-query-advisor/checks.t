#!/usr/bin/env perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More tests => 13;

use PerconaTest;
require "$trunk/bin/pt-query-advisor";

my @args = qw(--print-all --report-format full --group-by none --query);
my $query;

# #############################################################################
# Literals.
# #############################################################################

ok(
   no_diff(sub { pt_query_advisor::main(@args,
         'SELECT ip FROM tbl WHERE ip="127.0.0.1"') },
      't/pt-query-advisor/samples/lit-001.txt',
   ),
   'LIT.001 "IP"'
);

ok(
   no_diff(sub { pt_query_advisor::main(@args,
         'SELECT c FROM tbl WHERE c < 2010-02-15') },
      't/pt-query-advisor/samples/lit-002-01.txt',
   ),
   'LIT.002 YYYY-MM-DD'
);

ok(
   no_diff(sub { pt_query_advisor::main(@args,
         'SELECT c FROM tbl WHERE c=20100215') },
      't/pt-query-advisor/samples/lit-002-02.txt',
   ),
   'LIT.002 YYYYMMDD'
);

# #############################################################################
# Table list.
# #############################################################################

ok(
   no_diff(sub { pt_query_advisor::main(@args,
         'SELECT * FROM tbl WHERE id=1') },
      't/pt-query-advisor/samples/tbl-001-01.txt',
   ),
   'TBL.001 *'
);

ok(
   no_diff(sub { pt_query_advisor::main(@args,
         'SELECT tbl.* FROM tbl WHERE id=2') },
      't/pt-query-advisor/samples/tbl-001-02.txt',
   ),
   'TBL.001 tbl.*'
);

ok(
   no_diff(sub { pt_query_advisor::main(@args,
         'SELECT tbl.* foo, bar FROM tbl WHERE id=1') },
      't/pt-query-advisor/samples/tbl-002-01.txt',
   ),
   'TBL.002 tbl.* foo'
);

ok(
   no_diff(sub { pt_query_advisor::main(@args,
         'SELECT tbl.* AS foo, bar FROM tbl WHERE id=2') },
      't/pt-query-advisor/samples/tbl-002-02.txt',
   ),
   'TBL.002 tbl.* AS foo'
);

# #############################################################################
# Query.
# #############################################################################

ok(
   no_diff(sub { pt_query_advisor::main(@args,
         'insert into foo values ("bar")') },
      't/pt-query-advisor/samples/qry-001-01.txt',
   ),
   'QRY.001 INSERT'
);

ok(
   no_diff(sub { pt_query_advisor::main(@args,
         'replace into foo values ("bar")') },
      't/pt-query-advisor/samples/qry-001-02.txt',
   ),
   'QRY.001 REPLACE'
);

# #############################################################################
# Subqueries.
# #############################################################################

ok(
   no_diff(sub { pt_query_advisor::main(@args,
         'select t from w where i=1 or i in (select * from j)') },
      't/pt-query-advisor/samples/sub-001-01.txt',
   ),
   'SUB.001'
);


# #############################################################################
# JOIN stuff.
# #############################################################################

$query = "SELECT * FROM   `wibble_chapter`
   INNER JOIN `wibble_series` AS `wibble_chapter__series`
   ON `wibble_chapter`.`series_id` = `wibble_chapter__series`.`id`,
   `wibble_series`,
   `auth_user`
   WHERE  ( `wibble_chapter`.`chapnum` = 63.0
      AND `wibble_chapter`.`status` = 1
      AND `wibble_chapter__series`.`title` = 'bibble' )
      AND `wibble_chapter`.`series_id` = `wibble_series`.`id`
      AND `wibble_series`.`poster_id` = `auth_user`.`id`
      ORDER  BY `wibble_chapter`.`create_time` DESC
      LIMIT  1";

ok(
   no_diff(sub { pt_query_advisor::main(@args, $query) },
      't/pt-query-advisor/samples/joi-001-002-01.txt',
   ),
   'JOI.001 and JOI.002'
);



# #############################################################################
# CLA.* rules
# #############################################################################

ok(
   no_diff(sub { pt_query_advisor::main(@args,
         'select id from tbl1 join tbl2 using (a) group by tbl1.id, tbl2.id') },
      't/pt-query-advisor/samples/cla-006-01.txt',
   ),
   'CLA.001 and CLA.006'
);

ok(
   no_diff(sub { pt_query_advisor::main(@args,
         'select c1, c2 from t where i=1 order by c1 desc, c2 asc') },
      't/pt-query-advisor/samples/cla-007-01.txt',
   ),
   'CLA.007'
);

# #############################################################################
# Done.
# #############################################################################
exit;

#!/usr/bin/env perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More tests => 10;

use PerconaTest;
require "$trunk/bin/pt-table-usage";

my @args   = qw();
my $in     = "$trunk/t/pt-table-usage/samples/in";
my $out    = "t/pt-table-usage/samples/out";
my $output = '';

# ############################################################################
# Basic queries that parse without problems.
# ############################################################################
ok(
   no_diff(
      sub { pt_table_usage::main(@args, "$in/slow001.txt") },
      "$out/slow001.txt",
   ),
   'Analysis for slow001.txt'
);

ok(
   no_diff(
      sub { pt_table_usage::main(@args, "$in/slow002.txt") },
      "$out/slow002.txt",
   ),
   'Analysis for slow002.txt (issue 1237)'
);

ok(
   no_diff(
      sub { pt_table_usage::main(@args, '--query',
         'DROP TABLE IF EXISTS t') },
      "$out/drop-table-if-exists.txt",
   ),
   'DROP TABLE IF EXISTS'
);

ok(
   no_diff(
      sub { pt_table_usage::main(@args, '--query',
         "create table temp.5 (
            datetime DATETIME,
            posted DATETIME,
            PRIMARY KEY(datetime)
         )
         SELECT c FROM t WHERE id=1")
      },
      "$out/create001.txt",
   ),
   'CREATE..SELECT'
);

ok(
   no_diff(
      sub { pt_table_usage::main(@args, '--query',
         "select a.dt,a.hr,a.count 
            from temp.temp6 a left join n.type b using (dt,hr) 
            where b.type is null OR b.type=0")
      },
      "$out/query001.txt",
   ),
   'Multi-column USING'
);

ok(
   no_diff(
      sub { pt_table_usage::main(@args, '--query',
         "SELECT dt.datetime, MAX(re.pd) AS pd FROM d1.t1 t1a INNER JOIN d2.t2 t2a ON CONCAT(t1.a, ' ', t2.a) = t1.datetime INNER JOIN d3.t3 t3a ON t1a.c = t3a.c GROUP BY t1.datetime");
      },
      "$out/query002.txt",
   ),
   'Function in JOIN clause'
);

# ############################################################################
# --id-attribute
# ############################################################################
ok(
   no_diff(
      sub { pt_table_usage::main(@args, "$in/slow003.txt",
         qw(--id-attribute ts)) },
      "$out/slow003-003.txt",
   ),
   'Analysis for slow003.txt with --id-attribute'
);

# ############################################################################
# --constant-data-value
# ############################################################################
$output = output(
   sub { pt_table_usage::main('--query', 'INSERT INTO t VALUES (42)',
      qw(--constant-data-value <const>)) },
);
like(
   $output,
   qr/SELECT <const>/,
   "--constant-data-value"
);

$output = output(
   sub { pt_table_usage::main('--query', 'INSERT INTO t VALUES (42)',
      qw(--constant-data-value), "") },
);
like(
   $output,
   qr/^SELECT\s+$/m,
   '--constant-data-value ""'
);

# ############################################################################
# Queries with tables that can't be resolved.
# ############################################################################

# The tables in the WHERE can't be resolved so there's no WHERE access listed.
ok(
   no_diff(
      sub { pt_table_usage::main(@args, "$in/slow003.txt") },
      "$out/slow003-001.txt",
   ),
   'Analysis for slow003.txt'
);

# #############################################################################
# Done.
# #############################################################################
exit;

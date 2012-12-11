#!/usr/bin/perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More;

use TextResultSetParser();
use MySQLConfigComparer;
use MySQLConfig;
use PerconaTest;

use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

my $trp = new TextResultSetParser();
my $cc  = new MySQLConfigComparer();
my $c1;
my $c2;

my $diff;
my $missing;
my $output;
my $sample = "t/lib/samples/configs/";

sub diff {
   my ( @configs ) = @_;
   my $diffs = $cc->diff(
      configs => \@configs,
   );
   return $diffs;
}

sub missing {
   my ( @configs ) = @_;
   my $missing= $cc->missing(
      configs => \@configs,
   );
   return $missing;
}

$c1 = new MySQLConfig(
   file                => "$trunk/$sample/mysqldhelp001.txt",
   TextResultSetParser => $trp,
);
is_deeply(
   diff($c1, $c1),
   undef,
   "mysqld config does not differ with itself"
);

$c2 = new MySQLConfig(
   result_set => [['query_cache_size', 0]],
);
is_deeply(
   diff($c2, $c2),
   undef,
   "SHOW VARS config does not differ with itself"
);

$c2 = new MySQLConfig(
   result_set => [['query_cache_size', 1024]],
);
is_deeply(
   diff($c1, $c2),
   {
      'query_cache_size' => [0, 1024],
   },
   "diff() sees a difference"
);

# #############################################################################
# Compare one config against another.
# #############################################################################
$c1 = new MySQLConfig(
   file => "$trunk/$sample/mysqldhelp001.txt",
   TextResultSetParser => $trp,
);
$c2 = new MySQLConfig(
   file => "$trunk/$sample/mysqldhelp002.txt",
   TextResultSetParser => $trp,
);

$diff = diff($c1, $c2);
is_deeply(
   $diff,
   {
      basedir => [
          '/home/daniel/mysql_binaries/mysql-5.0.82-linux-x86_64-glibc23',
          '/usr/'
      ],
      character_sets_dir => [
          '/home/daniel/mysql_binaries/mysql-5.0.82-linux-x86_64-glibc23/share/mysql/charsets/',
          '/usr/share/mysql/charsets/'
      ],
      connect_timeout      => ['10','5'],
      datadir              => ['/tmp/12345/data/', '/mnt/data/mysql/'],
      innodb_data_home_dir => ['/tmp/12345/data',''],
      innodb_file_per_table=> ['FALSE', 'TRUE'],
      innodb_flush_log_at_trx_commit => ['1','2'],
      innodb_flush_method  => ['','O_DIRECT'],
      innodb_log_file_size => ['5242880','67108864'],
      innodb_log_group_home_dir => ['/tmp/12345/data', ''],
      key_buffer_size      => ['16777216','8388600'],
      language             => [
          '/home/daniel/mysql_binaries/mysql-5.0.82-linux-x86_64-glibc23/share/mysql/english/',
          '/usr/share/mysql/english/'
      ],
      log_bin           => ['mysql-bin', 'sl1-bin'],
      log_slave_updates => ['TRUE','FALSE'],
      max_binlog_cache_size => [
         '18446744073709547520',
         '18446744073709551615'
         ],
      myisam_max_sort_file_size => [
         '9223372036853727232',
         '9223372036854775807'
      ],
      old_passwords => ['FALSE','TRUE'],
      pid_file    => [
          '/tmp/12345/data/mysql_sandbox12345.pid',
          '/mnt/data/mysql/sl1.pid'
      ],
      port        => ['12345','3306'],
      range_alloc_block_size => ['4096','2048'],
      relay_log   => ['mysql-relay-bin',''],
      report_host => ['127.0.0.1', ''],
      report_port => ['12345','3306'],
      server_id   => ['12345','1'],
      socket      => [
          '/tmp/12345/mysql_sandbox12345.sock',
          '/mnt/data/mysql/mysql.sock'
      ],
      ssl         => ['FALSE','TRUE'],
      ssl_ca      => ['','/opt/mysql.pdns/.cert/ca-cert.pem'],
      ssl_cert    => ['','/opt/mysql.pdns/.cert/server-cert.pem'],
      ssl_key     => ['','/opt/mysql.pdns/.cert/server-key.pem'],
   },
   "Diff two different configs"
);

# #############################################################################
# Missing vars.
# #############################################################################
$c1 = new MySQLConfig(
   result_set => [['query_cache_size', 1024]],
);
$c2 = new MySQLConfig(
   result_set => [],
   TextResultSetParser => $trp,
);

$missing = missing($c1, $c2);
is_deeply(
   $missing,
   {
      'query_cache_size' =>[qw(1 0)],
   },
   "Missing var, right"
) or print Dumper($missing);

$c2 = new MySQLConfig(
   result_set => [['query_cache_size', 1024]],
);
$missing = missing($c1, $c2);
is_deeply(
   $missing,
   undef,
   "No missing vars"
);

$c2 = new MySQLConfig(
   result_set => [['query_cache_size', 1024], ['foo', 1]],
);
$missing = missing($c1, $c2);
is_deeply(
   $missing,
   {
      'foo' => [qw(0 1)],
   },
   "Missing var, left"
);


# #############################################################################
# Some tricky vars.
# #############################################################################
$c1 = new MySQLConfig(
   result_set => [['log_error', undef]],
   format     => 'optiona_file',
);
$c2 = new MySQLConfig(
   result_set => [['log_error', '/tmp/12345/data/mysqld.log']],
   format     => 'show_variables',
);
$diff = diff($c1, $c2);
is_deeply(
   $diff,
   undef,
   "log_error: undef, value"
);

$c1 = new MySQLConfig(
   result_set => [['log_error', '/tmp/12345/data/mysqld.log']],
   format     => 'show_variables',
);
$c2 = new MySQLConfig(
   result_set => [['log_error', undef]],
   format     => 'option_file',
);
$diff = diff($c1, $c2);
is_deeply(
   $diff,
   undef,
   "log_error: value, undef"
);

$c1 = new MySQLConfig(
   result_set => [[qw(log_bin mysql-bin)]],
   format     => 'option_file',
);
$c2 = new MySQLConfig(
   result_set => [[qw(log_bin ON)]],
   format     => 'show_variables',
);

$diff = diff($c1, $c2);
is_deeply(
   $diff,
   undef,
   "Any value is true (e.g. log-bin)"
);

# ############################################################################
# Vars with default values.
# ############################################################################
$c1 = new MySQLConfig(
   result_set => [
      ['log',        ''],
      ['log_bin',    ''],
   ],
   type => 'option_file',
);
$c2 = new MySQLConfig(
   result_set => [
      ['log',        '/opt/mysql/data/mysqld.log'],
      ['log_bin',    '/opt/mysql/data/mysql-bin' ],
   ],
   type => 'show_variables',
);
is_deeply(
   diff($c2, $c2),
   undef,
   "Variables with optional values"
);

# ############################################################################
# Vars with relative paths.
# ############################################################################

my $basedir = '/opt/mysql';
my $datadir = '/tmp/12345/data';

# This simulates a my.cnf.  We just need vars with relative paths, so no need
# to parse a real my.cnf with other vars that we don't need.
$c1 = new MySQLConfig(
   result_set => [
      ['basedir',    $basedir             ],  # must have this
      ['datadir',    $datadir             ],  # must have this
      ['language',   './share/english'    ],
      ['log_error',  'mysqld-error.log'   ],
   ],
); 

# This simulates SHOW VARIABLES.  Like $c1, we just need vars with relative
# paths.  But be sure to get real values because the whole point here is the
# different way these vars are listed in my.cnf vs. SHOW VARS.
$c2 = new MySQLConfig(
   result_set => [
      ['basedir',    $basedir                   ],  # must have this
      ['datadir',    $datadir                   ],  # must have this
      ['language',   "$basedir/share/english"   ],
      ['log_error',  "$datadir/mysqld-error.log"],
   ], 
); 

$diff = diff($c1, $c2);
is_deeply(
   $diff,
   undef,
   "Variables with relative paths"
) or print Dumper($diff);


# ############################################################################
# Compare 3 configs.
# ############################################################################
$c1 = new MySQLConfig(
   result_set => [['log_error', '/tmp/12345/data/mysqld.log']],
   format     => 'show_variables',
);
$c2 = new MySQLConfig(
   result_set => [['log_error', undef]],
   format     => 'option_file',
);
my $c3 = new MySQLConfig(
   result_set => [['log_error', '/tmp/12345/data/mysqld.log']],
   format     => 'show_variables',
);

$diff = diff($c1, $c2, $c3);
is_deeply(
   $diff,
   undef,
   "Compare 3 configs"
);

$c3 = new MySQLConfig(
   result_set => [['log_error', '/tmp/12345/data/mysql-error.log']],
   format     => 'show_variables',
);

$diff = diff($c1, $c2, $c3);
is_deeply(
   $diff,
   {
      log_error => [
         '/tmp/12345/data/mysqld.log',
         undef,
         '/tmp/12345/data/mysql-error.log',
      ],
   },
   "3 configs with a diff"
);

# ############################################################################
# Add to, override defaults.
# ############################################################################
$c1 = new MySQLConfig(
   result_set => [['log_error', 'foo']],
   format     => 'show_variables',
);
$c2 = new MySQLConfig(
   result_set => [['log_error', 'bar']],
   format     => 'show_variables',
);

{
   my $cc = new MySQLConfigComparer(
      ignore_variables => [qw(log_error)],
   );
   
   $diff = $cc->diff(
      configs => [$c1, $c2],
   );

   is_deeply(
      $diff,
      undef,
      "Ignore variables"
   ) or print Dumper($diff);
}

# ############################################################################
# https://bugs.launchpad.net/percona-toolkit/+bug/889739
# pt-config-diff doesn't diff quoted strings properly
# ############################################################################
$c1 = new MySQLConfig(
   file                => "$trunk/$sample/quoted_cnf.txt",
   TextResultSetParser => $trp,
);
$c2 = new MySQLConfig(
   file                => "$trunk/$sample/unquoted_cnf.txt",
   TextResultSetParser => $trp,
);
{
    my $diff = $cc->diff(
      configs => [$c1, $c2],
    );

    is_deeply(
        $diff,
        undef,
        "Values are the same regardless of quoting"
    ) or diag(Dumper($diff));
}
# #############################################################################
# Case insensitivity
# #############################################################################

$c1 = new MySQLConfig(
   result_set => [['binlog_format', 'MIXED']],
   format     => 'option_file',
);

$c2 = new MySQLConfig(
   result_set => [['binlog_format', 'mixed']],
   format     => 'option_file',
);

is_deeply(
   diff($c1, $c2),
   undef,
   "Case insensitivity is on by default"
);

my $case_cc = MySQLConfigComparer->new( ignore_case => undef, );

is_deeply(
   $case_cc->diff(configs => [$c1, $c2]),
   {
      binlog_format => [
         'MIXED',
         'mixed'
      ]
   },
   "..but can be turned off"
);

# #############################################################################
# Done.
# #############################################################################
{
   local *STDERR;
   open STDERR, '>', \$output;
   $cc->_d('Complete test coverage');
}
like(
   $output,
   qr/Complete test coverage/,
   '_d() works'
);

done_testing;

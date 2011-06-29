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
require "$trunk/bin/pt-table-checksum";

my $vp  = new VersionParser();
my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
else {
   plan tests => 4;
}

my $output;
my $cnf='/tmp/12345/my.sandbox.cnf';
my @args = ('-F', $cnf, 'h=127.1');

$sb->create_dbs($dbh, [qw(test)]);
$dbh->do('use test');
$dbh->do('create table t1 (i int) engine=myisam');
$dbh->do('create table t2 (i int) engine=innodb');

$output = output(
   sub { pt_table_checksum::main(@args,
         qw(--explain -d test --engines InnoDB)) },
);

is(
   $output,
"test     t2    CHECKSUM TABLE `test`.`t2`
",
   '--engines'
);


$output = output(
   sub { pt_table_checksum::main(@args,
         qw(--explain -d mysql --tables-regex user)) },
);
like(
   $output,
   qr/^mysql\s+user\s+/,
   "--tables-regex"
);

$output = output(
   sub { pt_table_checksum::main(@args,
         qw(--explain -d mysql --ignore-tables-regex user)) },
);
unlike(
   $output,
   qr/user/,
   "--ignore-tables-regex"
);

$output = output(
   sub { pt_table_checksum::main(@args,
         qw(--explain -d mysql --ignore-databases-regex mysql)) },
);
is(
   $output,
   "",
   "--ignore-databases-regex"
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
exit;

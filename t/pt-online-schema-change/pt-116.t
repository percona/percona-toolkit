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

use Data::Dumper;
use PerconaTest;
use Sandbox;
use SqlModes;
use File::Temp qw/ tempdir /;

plan tests => 8;

require "$trunk/bin/pt-online-schema-change";

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);

my $master_dbh = $sb->get_dbh_for('master');
my $master_dsn = 'h=127.1,P=12345,u=msandbox,p=msandbox';

if ( !$master_dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}

# The sandbox servers run with lock_wait_timeout=3 and it's not dynamic
# so we need to specify --set-vars innodb_lock_wait_timeout=3 else the
# tool will die.
my @args       = (qw(--set-vars innodb_lock_wait_timeout=3));
my $output;
my $exit_status;
my $sample  = "t/pt-online-schema-change/samples/";

$sb->load_file('master', "$sample/pt-116.sql");

my $dir = tempdir( CLEANUP => 1 );
($output, $exit_status) = full_output(
   sub { pt_online_schema_change::main(@args, "$master_dsn,D=test,t=t1",
         '--execute', 
         '--alter', "ADD UNIQUE INDEX unique_1 (notunique)",
         '--chunk-size', '1',
         ),
      },
   stderr => 1,
);

like(
      $output,
      qr/It seems like/s,
      "Need to specify use-insert-ignore",
);

($output, $exit_status) = full_output(
   sub { pt_online_schema_change::main(@args, "$master_dsn,D=test,t=t1",
         '--execute', 
         '--alter', "ADD UNIQUE INDEX unique_1 (notunique)",
         '--chunk-size', '1',
         '--nouse-insert-ignore',
         ),
      },
   stderr => 1,
);

like(
      $output,
      qr/Error copying rows from/s,
      "Error adding unique index not using insert ignore",
);

isnt(
    $exit_status,
    0,
    "Got error adding unique index (exit status != 0)",
);

# Check no data was deleted from the original table
my $rows = $master_dbh->selectrow_arrayref(
   "SELECT COUNT(*) FROM `test`.`t1`");
is(
   $rows->[0],
   3,
   "ALTER ADD UNIQUE key on a field having duplicated values"
) or diag(Dumper($rows));


#   # This test looks weird but since we added use-insert-ignore, we know in this particular
#   # case, having the testing dataset with repeated values for the field on which we are
#   # adding a unique will lose data.
#   # It is not the intention of this test to lose data, but we need to test the INSERT statement
#   # was created as expected.
($output, $exit_status) = full_output(
   sub { pt_online_schema_change::main(@args, "$master_dsn,D=test,t=t1",
         '--execute', 
         '--alter', "ADD UNIQUE INDEX unique_1 (notunique)",
         '--chunk-size', '1',
         '--use-insert-ignore',
         ),
      },
   stderr => 1,
);


like(
      $output,
      qr/Successfully altered/s,
      "Error adding unique index not using insert ignore",
);

is(
    $exit_status,
    0,
    "Added unique index and some rows got lost (exit status = 0)",
);

# Check no data was deleted from the original table
$rows = $master_dbh->selectrow_arrayref(
   "SELECT COUNT(*) FROM `test`.`t1`");
is(
   $rows->[0],
   2,
   "Added unique index and some rows got lost (row count = original - 1)",
) or diag(Dumper($rows));

$master_dbh->do("DROP DATABASE IF EXISTS test");

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;

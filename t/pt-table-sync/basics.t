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

use PerconaTest;
use Sandbox;
require "$trunk/bin/pt-table-sync";

my $output;
my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $master_dbh = $sb->get_dbh_for('master');
my $slave_dbh  = $sb->get_dbh_for('slave1');

if ( !$master_dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
elsif ( !$slave_dbh ) {
   plan skip_all => 'Cannot connect to sandbox slave';
}
else {
   plan tests => 9;
}

$sb->wipe_clean($master_dbh);
$sb->wipe_clean($slave_dbh);
$sb->create_dbs($master_dbh, [qw(test)]);

sub query_slave {
   return $slave_dbh->selectall_arrayref(@_, {Slice => {}});
}

sub run {
   my ($src, $dst, $other) = @_;
   my $output = output(
      sub {
         pt_table_sync::main(qw(--print --execute),
            "h=127.1,P=12345,u=msandbox,p=msandbox,D=test,t=$src",
            "h=127.1,P=12346,u=msandbox,p=msandbox,D=test,t=$dst",
            ($other ? split(" ", $other) : ())
         );
      },
      stderr => 1,
   );
   if ( $output ) {
      chomp $output;
      # Remove trace comments from end of change statements.
      $output = remove_traces($output);
   };
   return $output;
}

sub run_cmd {
   my ($src, $dst, $other) = @_;
   my $cmd = "$trunk/bin/pt-table-sync --print --execute h=127.1,P=12345,u=msandbox,p=msandbox,D=test,t=$src h=127.1,P=12346,D=test,t=$dst $other 2>&1";
   chomp($output=`$cmd`);
   return $output;
}

# #############################################################################
# Test basic master-slave syncing
# #############################################################################
$sb->load_file('master', 't/pt-table-sync/samples/before.sql');
$output = run('test1', 'test2', '');
like($output, qr/Can't make changes/, 'It dislikes changing a slave');

$output = run('test1', 'test2', '--no-bin-log');
is($output, "INSERT INTO `test`.`test2`(`a`, `b`) VALUES ('1', 'en');
INSERT INTO `test`.`test2`(`a`, `b`) VALUES ('2', 'ca');", 'No alg sync');
is_deeply(
   query_slave('select * from test.test2'),
   [ {   a => 1, b => 'en' }, { a => 2, b => 'ca' } ],
   'Synced OK with no alg'
);

# Save original MKDEBUG env because we modify it below.
my $dbg = $ENV{MKDEBUG};

$sb->load_file('master', 't/pt-table-sync/samples/before.sql');
$ENV{MKDEBUG} = 1;
$output = run_cmd('test1', 'test2', '--no-bin-log --chunk-size 1 --transaction --lock 1');
delete $ENV{MKDEBUG};
# TODO: rewrite this poor test
like(
   $output,
   qr/START TRANSACTION/,
   'Nibble with transactions and locking'
);
is_deeply(
   query_slave('select * from test.test2'),
   [ {   a => 1, b => 'en' }, { a => 2, b => 'ca' } ],
   'Synced OK with Nibble'
);

# Sync tables that have values with leading zeroes
$ENV{MKDEBUG} = 1;
$output = run('test3', 'test4', '--print --no-bin-log --verbose --function MD5');
delete $ENV{MKDEBUG};
like(
   $output,
   qr/UPDATE `test`.`test4`.*51707/,
   'Found the first row',
);
like(
   $output,
   qr/UPDATE `test`.`test4`.*'001'/,
   'Found the second row',
);
like(
   $output,
   qr/2\s+\S+\s+\S+\s+2\s+test.test3/,
   'Right number of rows to update',
);

# Sync a table with Nibble and a chunksize in data size, not number of rows
$output = run('test3', 'test4', '--chunk-size 1k --print --no-bin-log --verbose --function MD5');
# If it lived, it's OK.
ok($output, 'Synced with Nibble and data-size chunksize');

# Restore MKDEBUG env.
$ENV{MKDEBUG} = $dbg || 0;


# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
$sb->wipe_clean($slave_dbh);
exit;

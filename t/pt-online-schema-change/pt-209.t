#!/usr/bin/env perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use threads;

use English qw(-no_match_vars);
use Test::More;

use Data::Dumper;
use PerconaTest;
use Sandbox;
use SqlModes;
use File::Temp qw/ tempdir /;

require "$trunk/bin/pt-online-schema-change";

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $master_dbh = $sb->get_dbh_for('master');
my $master_dsn = 'h=127.1,P=12345,u=msandbox,p=msandbox';

if ( !$master_dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}

if ($sandbox_version lt '5.7') {
   plan skip_all => "RocksDB is only available on Percona Server 5.7.19+";
}

my $rows = $master_dbh->selectall_arrayref('SHOW ENGINES', {Slice=>{}});
my $rocksdb_enabled;
for my $row (@$rows) {
    if ($row->{engine} eq 'ROCKSDB') {
        $rocksdb_enabled = 1;
        last;
    }
}

if (!$rocksdb_enabled) {
   plan skip_all => "RocksDB engine is not available";
}

plan tests => 3;

# The sandbox servers run with lock_wait_timeout=3 and it's not dynamic
# so we need to specify --set-vars innodb_lock_wait_timeout=3 else the
# tool will die.
my @args       = (qw(--set-vars innodb_lock_wait_timeout=3));
my $output;
my $exit_status;
my $sample  = "t/pt-online-schema-change/samples/";

$sb->load_file('master', "$sample/pt-209.sql");

($output, $exit_status) = full_output(
   sub { pt_online_schema_change::main(@args, "$master_dsn,D=test,t=t1",
         '--execute', 
         '--alter', "ADD CONSTRAINT fk_some_id FOREIGN KEY (some_id) REFERENCES some(id)`",
         ),
      },
);

isnt(
      $exit_status,
      0,
      "PT-209 Altering RocksDB table adding a foreign key exit status != 0",
);

like(
      $output,
      qr/FOREIGN KEYS are not supported by the RocksDB engine/s,
      "PT-209 Message cannot add FKs to a RocksDB table",
);

$master_dbh->do("DROP DATABASE IF EXISTS test");

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;

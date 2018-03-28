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

plan tests => 6;

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

$sb->load_file('master', "$sample/pt-153.sql");

($output, $exit_status) = full_output(
   sub { pt_online_schema_change::main(@args, "$master_dsn,D=test,t=t1",
         '--execute', 
         '--alter', "ADD UNIQUE INDEX c1 (f2, f3)",
         ),
      },
);

isnt(
      $exit_status,
      0,
      "PT-153 Adding unique index exit status != 0.",
);

like(
      $output,
      qr/You are trying to add an unique key. This can result in data loss if the data is not unique/s,
      "PT-153 Adding unique index warning message.",
);

($output, $exit_status) = full_output(
   sub { pt_online_schema_change::main(@args, "$master_dsn,D=test,t=t1",
         '--execute', 
         '--alter', "ADD UNIQUE INDEX c1 (f2, f3), PRIMARY KEY (f3), UNIQUE KEY k2 (f3)",
         ),
      },
);

isnt(
      $exit_status,
      0,
      "PT-153 Adding multiple unique indexes exit status != 0.",
);

like(
      $output,
      qr/You are trying to add an unique key. This can result in data loss if the data is not unique/s,
      "PT-153 Adding multiple unique indexes warning message.",
);

like(
      $output,
      qr/SELECT IF\(COUNT\(DISTINCT f2, f3\).*?SELECT IF\(COUNT\(DISTINCT f3\)/s,
      "PT-153 Adding multiple unique indexes -> multime example queries.",
);

$master_dbh->do("DROP DATABASE IF EXISTS test");

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;

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
use Time::HiRes qw(time);

use PerconaTest;
use Sandbox;
use Data::Dumper;
require "$trunk/bin/pt-archiver";

my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $source_dbh = $sb->get_dbh_for('source');
my $replica1_dbh = $sb->get_dbh_for('replica1');

if ( !$source_dbh ) {
   plan skip_all => 'Cannot connect to sandbox source';
}
elsif ( !$replica1_dbh ) {
   plan skip_all => 'Cannot connect to sandbox replica1';
}

my $output;
my $cnf  = "/tmp/12345/my.sandbox.cnf";
my @args = qw(--no-delete --where 1=1 --progress 1 --no-check-charset);
my $delay = 10;

# Prepare tables and replica lag
sub prepare {
   $replica1_dbh->do("STOP ${replica_name}");
   $source_dbh->do("RESET ${source_reset}");
   $replica1_dbh->do("RESET ${replica_name}");
   $replica1_dbh->do("START ${replica_name}");

   $source_dbh->do("DROP DATABASE IF EXISTS test");
   $source_dbh->do("CREATE DATABASE test");
   $source_dbh->do("CREATE TABLE test.test(id INT)");
   $source_dbh->do("CREATE TABLE test.actor LIKE sakila.actor");

   $replica1_dbh->do("STOP ${replica_name}");
   $replica1_dbh->do("CHANGE ${source_change} TO ${source_name}_DELAY=${delay}");
   $replica1_dbh->do("START ${replica_name}");
   $source_dbh->do("INSERT INTO test.test VALUES(1)");

   # Sleeping to ensure that replica is lagging when pt-archiver starts
   sleep(3);
}

prepare();

$output = output(
   sub {
      pt_archiver::main(@args,
         '--source', "D=sakila,t=actor,F=$cnf",
         '--dest', "D=test,t=actor,F=$cnf",
         '--check-replica-lag', 'h=127.0.0.1,P=12346,u=msandbox,p=msandbox'
      )
   },
   stderr => 1
);

like(
   $output,
   qr/Sleeping: replica lag for server/,
   'Lag check works'
) or diag($output);

unlike(
   $output,
   qr/Option --check-slave-lag is deprecated and will be removed in future versions./,
   'Deprecation warning not printed for option --check-replica-lag'
) or diag($output);

# Option --check-replica-lag specified two times

prepare();

$output = output(
   sub {
      pt_archiver::main(@args,
         '--source', "D=sakila,t=actor,F=$cnf",
         '--dest', "D=test,t=actor,F=$cnf",
         '--check-replica-lag', 'h=127.0.0.1,P=12346,u=msandbox,p=msandbox',
         '--check-replica-lag', 'h=127.0.0.1,P=12347,u=msandbox,p=msandbox'
      )
   },
   stderr => 1
);

like(
   $output,
   qr/Sleeping: replica lag for server/,
   'Lag check works when --check-replica-lag provided two times'
) or diag($output);

unlike(
   $output,
   qr/Option --check-slave-lag is deprecated and will be removed in future versions./,
   'Deprecation warning not printed when option --check-replica-lag provided two times'
) or diag($output);

# Option --check-replica-lag specified two times

prepare();

$output = output(
   sub {
      pt_archiver::main(@args,
         '--source', "D=sakila,t=actor,F=$cnf",
         '--dest', "D=test,t=actor,F=$cnf",
         '--check-replica-lag', 'h=127.0.0.1,P=12347,u=msandbox,p=msandbox',
         '--check-replica-lag', 'h=127.0.0.1,P=12346,u=msandbox,p=msandbox'
      )
   },
   stderr => 1
);

like(
   $output,
   qr/Sleeping: replica lag for server/,
   'Test 2: Lag check works when --check-replica-lag provided two times'
) or diag($output);

unlike(
   $output,
   qr/Option --check-slave-lag is deprecated and will be removed in future versions./,
   'Test 2: Deprecation warning not printed when option --check-replica-lag provided two times'
) or diag($output);

# Warning printed for --check-slave-lag but the option works

prepare();

$output = output(
   sub {
      pt_archiver::main(@args,
         '--source', "D=sakila,t=actor,F=$cnf",
         '--dest', "D=test,t=actor,F=$cnf",
         '--check-slave-lag', 'h=127.0.0.1,P=12346,u=msandbox,p=msandbox'
      )
   },
   stderr => 1
);

like(
   $output,
   qr/Sleeping: replica lag for server/,
   'Lag check works for deprecated option'
) or diag($output);

like(
   $output,
   qr/Option --check-slave-lag is deprecated and will be removed in future versions./,
   'Deprecation warning printed for --check-slave-lag'
) or diag($output);

# Option --check-slave-lag specified two times

prepare();

$output = output(
   sub {
      pt_archiver::main(@args,
         '--source', "D=sakila,t=actor,F=$cnf",
         '--dest', "D=test,t=actor,F=$cnf",
         '--check-slave-lag', 'h=127.0.0.1,P=12346,u=msandbox,p=msandbox',
         '--check-slave-lag', 'h=127.0.0.1,P=12347,u=msandbox,p=msandbox'
      )
   },
   stderr => 1
);

like(
   $output,
   qr/Sleeping: replica lag for server/,
   'Lag check works when option --check-slave-lag provided two times'
) or diag($output);

like(
   $output,
   qr/Option --check-slave-lag is deprecated and will be removed in future versions./,
   'Deprecation warning printed for option --check-slave-lag provided two times'
) or diag($output);

# Mix of --check-slave-lag amd --check-replica-lag options

prepare();

$output = output(
   sub {
      pt_archiver::main(@args,
         '--source', "D=sakila,t=actor,F=$cnf",
         '--dest', "D=test,t=actor,F=$cnf",
         '--check-replica-lag', 'h=127.0.0.1,P=12346,u=msandbox,p=msandbox',
         '--check-slave-lag', 'h=127.0.0.1,P=12347,u=msandbox,p=msandbox'
      )
   },
   stderr => 1
);

like(
   $output,
   qr/Sleeping: replica lag for server/,
   'Lag check works for --check-replica-lag when --check-slave-lag also provided'
) or diag($output);

like(
   $output,
   qr/Option --check-slave-lag is deprecated and will be removed in future versions./,
   'Deprecation warning printed for option --check-slave-lag'
) or diag($output);

# Mix of --check-slave-lag amd --check-replica-lag options

prepare();

$output = output(
   sub {
      pt_archiver::main(@args,
         '--source', "D=sakila,t=actor,F=$cnf",
         '--dest', "D=test,t=actor,F=$cnf",
         '--check-slave-lag', 'h=127.0.0.1,P=12346,u=msandbox,p=msandbox',
         '--check-replica-lag', 'h=127.0.0.1,P=12347,u=msandbox,p=msandbox'
      )
   },
   stderr => 1
);

like(
   $output,
   qr/Sleeping: replica lag for server/,
   'Lag check works for --check-slave-lag when --check-replica-lag also provided'
) or diag($output);

like(
   $output,
   qr/Option --check-slave-lag is deprecated and will be removed in future versions./,
   'Deprecation warning printed for option --check-slave-lag'
) or diag($output);

# #############################################################################
# Done.
# #############################################################################
$replica1_dbh->do("STOP ${replica_name}");
$source_dbh->do("RESET ${source_reset}");
$replica1_dbh->do("RESET ${replica_name}");
$replica1_dbh->do("START ${replica_name}");

$sb->wipe_clean($source_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");

done_testing;

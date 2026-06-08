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
require "$trunk/bin/pt-deadlock-logger";

my $dp   = new DSNParser(opts=>$dsn_opts);
my $sb   = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh1 = $sb->get_dbh_for('source', { PrintError => 0, RaiseError => 1, AutoCommit => 0 });
my $dbh2 = $sb->get_dbh_for('source', { PrintError => 0, RaiseError => 1, AutoCommit => 0 });

my ($output, $exit_code);
my $dsn  = $sb->dsn_for('source');
my @args = ($dsn, qw(--iterations 1));

# Testing if we are using DBD::mysql compiled with MariaDB library, which does not support enforcing SSL encryption
($output, $exit_code) = full_output(
   sub { pt_deadlock_logger::main("h=127.1,P=12345,D=sakila,t=film,u=msandbox,p=msandbox,s=1",
      qw(--iterations 1)
      );
   },
   stderr => 1,
);

if ( $exit_code == 0 || $output !~ /SSL connection error: Enforcing SSL encryption is not supported/ ) {
   plan skip_all => "Test requires DBD::mysql compiled with MariaDB library that does not support enforcing SSL encryption";
}
elsif ( !$dbh1 || !$dbh2 ) {
   plan skip_all => 'Cannot connect to sandbox source';
}
elsif ( $sandbox_version lt '8.0' ) {
   plan skip_all => "Requires MySQL 8.0 or newer";
}

$dbh1->commit;
$dbh2->commit;
$sb->wipe_clean($dbh1);
$sb->create_dbs($dbh1, ['test']);

# Set up the table for creating a deadlock.
$dbh1->do("create table test.dl(a int) engine=innodb");
$dbh1->do("insert into test.dl(a) values(0), (1)");
$dbh1->commit;
$dbh2->commit;
$dbh1->{InactiveDestroy} = 1;
$dbh2->{InactiveDestroy} = 1;

$dbh1->{mysql_auto_reconnect} = 1;
$dbh2->{mysql_auto_reconnect} = 1;

sub make_deadlock {
   # Fork off two children to deadlock against each other.
   my %children;
   foreach my $child ( 0..1 ) {
      my $pid = fork();
      if ( defined($pid) && $pid == 0 ) { # I am a child
         eval {
            my $dbh = ($dbh1, $dbh2)[$child];
            my @stmts = (
               "set transaction isolation level serializable",
               "begin",
               "select * from test.dl where a = $child",
               "update test.dl set a = $child where a <> $child",
            );
            foreach my $stmt (@stmts[0..2]) {
               $dbh->do($stmt);
            }
            sleep(1 + $child);
            $dbh->do($stmts[-1]);
         };
         if ( $EVAL_ERROR ) {
            if ( $EVAL_ERROR !~ m/Deadlock found/ ) {
               die $EVAL_ERROR;
            }
         }
         exit(0);
      }
      elsif ( !defined($pid) ) {
         die("Unable to fork for clearing deadlocks!\n");
      }

      # I already exited if I'm a child, so I'm the parent.
      $children{$child} = $pid;
   }

   # Wait for the children to exit.
   foreach my $child ( keys %children ) {
      my $pid = waitpid($children{$child}, 0);
   }
   eval {
       $dbh1->commit;
       $dbh1->disconnect();
   };
   eval {
       $dbh2->commit;
       $dbh2->disconnect();
   };
}

sub reconnect {
    my $dbh = shift;
    $dbh->disconnect();
    $dbh = $sb->get_dbh_for('source', { PrintError => 0, RaiseError => 1, AutoCommit => 0 });
    return $dbh;
}

$sb->do_as_root(
   'source',
   q/CREATE USER IF NOT EXISTS sha256_user@'%' IDENTIFIED WITH caching_sha2_password BY 'sha256_user%password' REQUIRE SSL/,
   q/GRANT ALL ON sakila.* TO sha256_user@'%'/,
   q/GRANT PROCESS ON *.* TO sha256_user@'%'/,
);

make_deadlock();

$dbh1 = reconnect($dbh1);
$dbh2 = reconnect($dbh2);

# Test that there is a deadlock
$output = $dbh1->selectrow_hashref('show /*!40101 engine*/ innodb status')->{status};
like($output, qr/WE ROLL BACK/, 'There was a deadlock');

($output, $exit_code) = full_output(
   sub {
      pt_deadlock_logger::main("h=127.1,P=12345,D=sakila,t=film,u=sha256_user,p=sha256_user%password,s=0",
      qw(--iterations 1));
   },
   stderr => 1,
);

isnt(
   $exit_code,
   0,
   "Error raised when SSL connection is not used"
) or diag($output);

like(
   $output,
   qr/Access denied/,
   'Secure connection error raised when no SSL connection used'
) or diag($output);

($output, $exit_code) = full_output(
   sub {
      pt_deadlock_logger::main("h=127.1,P=12345,D=sakila,t=film,u=sha256_user,p=sha256_user%password,s=1,o=1",
      qw(--iterations 1));
   },
   stderr => 1,
);

is(
   $exit_code,
   0,
   "No error for user, identified with caching_sha2_password"
) or diag($output);

unlike(
   $output,
   qr/Access denied/,
   'No secure connection error'
) or diag($output);

like(
   $output,
   qr/127\.1.+msandbox.+GEN_CLUST_INDEX/,
   'Deadlock logger prints the output'
) or diag($output);

($output, $exit_code) = full_output(
   sub {
      pt_deadlock_logger::main(
         qw(--host 127.1 --port 12345 --user sha256_user),
         qw(--password sha256_user%password --mysql_ssl 1 --mysql_ssl_optional=1),
         qw(--iterations 1));
   },
   stderr => 1,
);

is(
   $exit_code,
   0,
   "No error for user, identified with caching_sha2_password with option --mysql_ssl"
) or diag($output);

unlike(
   $output,
   qr/Access denied/,
   'No secure connection error with option --mysql_ssl'
) or diag($output);

like(
   $output,
   qr/127\.1.+msandbox.+GEN_CLUST_INDEX/,
   'Deadlock logger prints the output with option --mysql_ssl'
) or diag($output);

($output, $exit_code) = full_output(
   sub {
      pt_deadlock_logger::main("F=t/pt-archiver/samples/pt-191.cnf,h=127.1,P=12345,D=sakila,t=film,u=sha256_user,p=sha256_user%password,s=1,o=1",
      qw(--iterations 1));
   },
   stderr => 1,
);

is(
   $exit_code,
   0,
   "No error for SSL options in the configuration file"
) or diag($output);

unlike(
   $output,
   qr/Access denied/,
   'No secure connection error with correct SSL options in the configuration file'
) or diag($output);

($output, $exit_code) = full_output(
   sub {
      pt_deadlock_logger::main("F=t/pt-archiver/samples/pt-191-error.cnf,h=127.1,P=12345,D=sakila,t=film,u=sha256_user,p=sha256_user%password,s=1,o=1",
      qw(--iterations 1));
   },
   stderr => 1,
);

isnt(
   $exit_code,
   0,
   "Error for invalid SSL options in the configuration file"
) or diag($output);

like(
   $output,
   qr/SSL error: key values mismatch/,
   'SSL connection error with incorrect SSL options in the configuration file'
) or diag($output);

# #############################################################################
# Done.
# #############################################################################
$sb->do_as_root('source', q/DROP USER 'sha256_user'@'%'/);

$dbh1 = reconnect($dbh1);
$dbh2 = reconnect($dbh2);

$dbh1->commit;
$dbh2->commit;
$sb->wipe_clean($dbh1);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;

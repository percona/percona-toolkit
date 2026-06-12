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

require "$trunk/bin/pt-slave-find";

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $replica1_dbh = $sb->get_dbh_for('replica1');
my $replica2_dbh = $sb->get_dbh_for('replica2');

# This test is sensitive to ghost/old replicas created/destroyed by other
# tests.  So we stop the replicas, restart the source, and start everything
# again.  Hopefully this will return the env to its original state.
$replica2_dbh->do("STOP ${replica_name}");
$replica1_dbh->do("STOP ${replica_name}");
diag(`/tmp/12345/stop >/dev/null`);
diag(`/tmp/12345/start >/dev/null`);
$replica1_dbh->do("START ${replica_name}");
$replica2_dbh->do("START ${replica_name}");

my $source_dbh = $sb->get_dbh_for('source');

if ( !$source_dbh ) {
   plan skip_all => 'Cannot connect to sandbox source';
}
elsif ( !$replica1_dbh ) {
   plan skip_all => 'Cannot connect to sandbox replica';
}
elsif ( !$replica2_dbh ) {
   plan skip_all => 'Cannot connect to second sandbox replica';
}
else {
   plan tests => 14;
}

my @args = ('h=127.0.0.1,P=12345,u=msandbox,p=msandbox,s=1');

my $output = `$trunk/bin/pt-slave-find --help`;
like($output, qr/Prompt for a password/, 'It compiles');

# Double check that we're setup correctly.
my $row = $replica2_dbh->selectall_arrayref("SHOW ${replica_name} STATUS", {Slice => {}});
is(
   $row->[0]->{"${source_name}_port"},
   '12346',
   'replica2 is replica of replica1'
) or diag(Dumper($row));

$output = `$trunk/bin/pt-slave-find -h 127.0.0.1 -P 12345 -u msandbox -p msandbox s=1 --report-format hostname`;
my $expected = <<EOF;
127.0.0.1:12345
+- 127.0.0.1:12346
   +- 127.0.0.1:12347
EOF
is($output, $expected, 'Source with replica and replica of replica');

###############################################################################
# Test --slave-user and --slave-password options
###############################################################################
# Create a new user that is going to be replicated on replicas.
if ($sandbox_version eq '8.0') {
    $sb->do_as_root("replica1", q/CREATE USER 'replica_user'@'localhost' IDENTIFIED WITH mysql_native_password BY 'replica_password'/);
} else {
    $sb->do_as_root("replica1", q/CREATE USER 'replica_user'@'localhost' IDENTIFIED BY 'replica_password'/);
}
$sb->do_as_root("replica1", q/GRANT REPLICATION CLIENT ON *.* TO 'replica_user'@'localhost'/);
$sb->do_as_root("replica1", q/GRANT REPLICATION SLAVE ON *.* TO 'replica_user'@'localhost'/);
$sb->do_as_root("replica1", q/FLUSH PRIVILEGES/);                

$sb->wait_for_replicas();

# Ensure we cannot connect to replicas using standard credentials
# Since replica2 is a replica of replica1, removing the user from the replica1 will remove
# the user also from replica2
$sb->do_as_root("replica1", q/RENAME USER 'msandbox'@'%' TO 'msandbox_old'@'%'/);
$sb->do_as_root("replica1", q/FLUSH PRIVILEGES/);
$sb->do_as_root("replica1", q/FLUSH TABLES/);

$output = `$trunk/bin/pt-replica-find -h 127.0.0.1 -P 12345 -u msandbox -p msandbox s=1 --report-format hostname --slave-user replica_user --slave-password replica_password 2>/dev/null`;
$expected = <<EOF;
127.0.0.1:12345
+- 127.0.0.1:12346
   +- 127.0.0.1:12347
EOF

is(
   $output,
   $expected,
   'Source with replica and replica of replica with --slave-user/--slave-password'
) or diag($output);

$output = `$trunk/bin/pt-replica-find -h 127.0.0.1 -P 12345 -u msandbox -p msandbox s=1 --report-format hostname --slave-user replica_user --slave-password replica_password 2>&1`;

like(
   $output,
   qr/\+- 127.0.0.1:12347/,
   'Test 2: Source with replica and replica of replica with --slave-user/--slave-password'
) or diag($output);

like(
   $output,
   qr/Option --slave-user is deprecated and will be removed in future versions./,
   'Deprecation warning printed for option --slave-user'
) or diag($output);

like(
   $output,
   qr/Option --slave-password is deprecated and will be removed in future versions./,
   'Deprecation warning printed for option --slave-password'
) or diag($output);

# Repeat the basic test with deprecated --slave-user and --slave-password
# Drop test user
$sb->do_as_root("replica1", q/DROP USER 'replica_user'@'localhost'/);
$sb->do_as_root("replica1", q/FLUSH PRIVILEGES/);

# Restore privilegs for the other tests
$sb->do_as_root("replica1", q/RENAME USER 'msandbox_old'@'%' TO 'msandbox'@'%'/);
$sb->do_as_root("source", q/FLUSH PRIVILEGES/);                
$sb->do_as_root("source", q/FLUSH TABLES/);

###############################################################################
# Test --resolve-hostname option (we don't know the hostname of the test
# machine so we settle for any non null string)
###############################################################################
$output = `$trunk/bin/pt-slave-find -h 127.0.0.1 -P 12345 -u msandbox -p msandbox --report-format hostname --resolve-address s=1`;
like (   
   $output,
   qr/127\.0\.0\.1:12345\s+\(\w+\)/s,
   "--resolve-address option"
) or diag($output);

# #########################################################################
# Issue 391: Add --pid option to all scripts
# #########################################################################
`touch /tmp/mk-script.pid`;
$output = `$trunk/bin/pt-slave-find -h 127.0.0.1 -P 12345 -u msandbox -p msandbox --pid /tmp/mk-script.pid 2>&1`;
like(
   $output,
   qr{PID file /tmp/mk-script.pid exists},
   'Dies if PID file already exists (issue 391)'
);
`rm -rf /tmp/mk-script.pid`;


# #############################################################################
# Summary report format.
# #############################################################################
my $outfile = "/tmp/mk-replica-find-output.txt";
#diag(`rm -rf $outfile >/dev/null`);
diag(`rm -rf $outfile`);

$output = output(
   sub { pt_replica_find::main(@args) },
   file => $outfile,
);

open my $fh, "<", $outfile or die $!;

my $result = do { local $/; <$fh> }; #"

$result =~ s/Version.*/Version/g;
$result =~ s/Uptime.*/Uptime/g;
$result =~ s/[0-9]* seconds/0 seconds/g;
$result =~ s/Binary logging.*/Binary logging/g;
$result =~ s/Replication     Is a slave, has 1 slaves connected, is.*/Replication     Is a slave, has 1 slaves connected, is/g;
$result =~ s/Replication     Is a replica, has 1 replicas connected, is.*/Replication     Is a replica, has 1 replicas connected, is/g;

my $innodb_re = qr/InnoDB version\s+(.*)/;
my (@innodb_versions) = $result =~ /$innodb_re/g;
$result =~ s/$innodb_re/InnoDB version  BUILTIN/g;

my $source_version = VersionParser->new($source_dbh);
my $replica_version  = VersionParser->new($replica1_dbh);
my $replica2_version = VersionParser->new($replica2_dbh);

is(
   $innodb_versions[0],
   $source_version->innodb_version(),
   "pt-slave-find gets the right InnoDB version for the source"
);

is(
   $innodb_versions[1],
   $replica_version->innodb_version(),
   "...and for the first replica"
) or diag($output);

is(
   $innodb_versions[2],
   $replica2_version->innodb_version(),
   "...and for the second replica"
);

ok(
   no_diff($result, ($sandbox_version ge '5.1'
      ? "t/pt-replica-find/samples/summary001.txt"
      : "t/pt-replica-find/samples/summary001-5.0.txt"), cmd_output => 1, keep_output => 1, update_samples => 1),
   "Summary report format",
) or diag($result);

# #############################################################################
# Done.
# #############################################################################
diag(`rm -rf $outfile >/dev/null`);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;

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

require "$trunk/bin/pt-slave-find";

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $slave1_dbh = $sb->get_dbh_for('slave1');
my $slave2_dbh = $sb->get_dbh_for('slave2');

# This test is sensitive to ghost/old slaves created/destroyed by other
# tests.  So we stop the slaves, restart the master, and start everything
# again.  Hopefully this will return the env to its original state.
$slave2_dbh->do("STOP SLAVE");
$slave1_dbh->do("STOP SLAVE");
diag(`/tmp/12345/stop >/dev/null`);
diag(`/tmp/12345/start >/dev/null`);
$slave1_dbh->do("START SLAVE");
$slave2_dbh->do("START SLAVE");

my $master_dbh = $sb->get_dbh_for('master');

if ( !$master_dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
elsif ( !$slave1_dbh ) {
   plan skip_all => 'Cannot connect to sandbox slave';
}
elsif ( !$slave2_dbh ) {
   plan skip_all => 'Cannot connect to second sandbox slave';
}
else {
   plan tests => 10;
}

my @args = ('h=127.0.0.1,P=12345,u=msandbox,p=msandbox');

my $output = `$trunk/bin/pt-slave-find --help`;
like($output, qr/Prompt for a password/, 'It compiles');

# Double check that we're setup correctly.
my $row = $slave2_dbh->selectall_arrayref('SHOW SLAVE STATUS', {Slice => {}});
is(
   $row->[0]->{master_port},
   '12346',
   'slave2 is slave of slave1'
);

$output = `$trunk/bin/pt-slave-find -h 127.0.0.1 -P 12345 -u msandbox -p msandbox --report-format hostname`;
my $expected = <<EOF;
127.0.0.1:12345
+- 127.0.0.1:12346
   +- 127.0.0.1:12347
EOF
is($output, $expected, 'Master with slave and slave of slave');

###############################################################################
# Test --resolve-hostname option (we don't know the hostname of the test
# machine so we settle for any non null string)
###############################################################################
$output = `$trunk/bin/pt-slave-find -h 127.0.0.1 -P 12345 -u msandbox -p msandbox --report-format hostname --resolve-address`;
like (   
   $output,
   qr/127\.0\.0\.1:12345\s+\(\w+\)/s,
   "--resolve-address option"
) or diag($output);

# #############################################################################
# Until MasterSlave::find_slave_hosts() is improved to overcome the problems
# with SHOW SLAVE HOSTS, this test won't work.
# #############################################################################
# Make slave2 slave of master.
#diag(`../../mk-slave-move/mk-slave-move --sibling-of-master h=127.1,P=12347`);
#$output = `perl ../mk-slave-find -h 127.0.0.1 -P 12345 -u msandbox -p msandbox`;
#$expected = <<EOF;
#127.0.0.1:12345
#+- 127.0.0.1:12346
#+- 127.0.0.1:12347
#EOF
#is($output, $expected, 'Master with two slaves');

# #########################################################################
# Issue 391: Add --pid option to all scripts
# #########################################################################
`touch /tmp/mk-script.pid`;
$output = `$trunk/bin/pt-slave-find -h 127.0.0.1 -P 12345 -u msandbox -p msandbox --pid /tmp/mk-script.pid 2>&1`;
like(
   $output,
   qr{PID file /tmp/mk-script.pid already exists},
   'Dies if PID file already exists (issue 391)'
);
`rm -rf /tmp/mk-script.pid`;


# #############################################################################
# Summary report format.
# #############################################################################
my $outfile = "/tmp/mk-slave-find-output.txt";
diag(`rm -rf $outfile >/dev/null`);

$output = output(
   sub { pt_slave_find::main(@args) },
   file => $outfile,
);

open my $fh, "<", $outfile or die $!;

my $result = do { local $/; <$fh> }; #"

$result =~ s/Version.*/Version/g;
$result =~ s/Uptime.*/Uptime/g;
$result =~ s/[0-9]* seconds/0 seconds/g;

my $innodb_re = qr/InnoDB version\s+(.*)/;
my (@innodb_versions) = $result =~ /$innodb_re/g;
$result =~ s/$innodb_re/InnoDB version  BUILTIN/g;

my $master_version = VersionParser->new($master_dbh);
my $slave_version  = VersionParser->new($slave1_dbh);
my $slave2_version = VersionParser->new($slave2_dbh);

is(
   $innodb_versions[0],
   $master_version->innodb_version(),
   "pt-slave-find gets the right InnoDB version for the master"
);

is(
   $innodb_versions[1],
   $slave_version->innodb_version(),
   "...and for the first slave"
);

is(
   $innodb_versions[2],
   $slave2_version->innodb_version(),
   "...and for the first slave"
);

ok(
   no_diff($result, ($sandbox_version ge '5.1'
      ? "t/pt-slave-find/samples/summary001.txt"
      : "t/pt-slave-find/samples/summary001-5.0.txt"), cmd_output => 1),
   "Summary report format",
);


# #############################################################################
# Done.
# #############################################################################
diag(`rm -rf $outfile >/dev/null`);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;

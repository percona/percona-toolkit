#!/usr/bin/env perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use PerconaTest;
use Sandbox;
use DSNParser;
require VersionParser;
use Test::More;
use File::Temp qw( tempdir );

local $ENV{PTDEBUG} = "";

my $dp         = new DSNParser(opts=>$dsn_opts);
my $sb         = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $master_dbh = $sb->get_dbh_for('master');
my $has_keyring_plugin;

my $db_flavor = VersionParser->new($master_dbh)->flavor();
if ( $db_flavor =~ m/Percona Server/ ) {
    my $rows = $master_dbh->selectall_hashref("SHOW PLUGINS", "name");
    while (my ($key, $values) = each %$rows) {
        if ($key =~ m/^keyring_/) {
            $has_keyring_plugin=1;
            last;
        }
    }
}

if ($has_keyring_plugin) {
    plan skip_all => 'Keyring plugins are enabled.';
}

my ($tool) = $PROGRAM_NAME =~ m/([\w-]+)\.t$/;

# mysqldump from earlier versions doesn't seem to work with 5.6,
# so use the actual mysqldump from each MySQL bin which should
# always be compatible with itself.
my $env = qq\CMD_MYSQLDUMP="$ENV{PERCONA_TOOLKIT_SANDBOX}/bin/mysqldump"\;

#
# --save-samples
#

my $dir = tempdir( "percona-testXXXXXXXX", CLEANUP => 1 );

`$env $trunk/bin/$tool --sleep 1 --save-samples $dir -- --defaults-file=/tmp/12345/my.sandbox.cnf`;

ok(
   -e $dir,
   "Using --save-samples doesn't mistakenly delete the target dir"
);

# If the box has a default my.cnf (e.g. /etc/my.cnf) there
# should be 15 files, else 14.
my @files = glob("$dir/*");
my $n_files = scalar @files;
ok(
   $n_files >= 15 && $n_files <= 18,
   "And leaves all files in there"
) or diag($n_files, `ls -l $dir`);

undef($dir);  # rm the dir because CLEANUP => 1

#
# --databases
#

my $out = `$env $trunk/bin/$tool --sleep 1 --databases mysql 2>/dev/null -- --defaults-file=/tmp/12345/my.sandbox.cnf`;

like(
   $out,
   qr/Database Tables Views SPs Trigs Funcs   FKs Partn\s+\Qmysql\E/,
   "--databases works"
);

like(
   $out,
   qr/# InnoDB #.*Version.*# MyISAM #/s,
   "InnoDB section present"
);

my $users_count = 2;
if ($ENV{FORK} || "" eq 'mariadb') {
    $users_count = 8;
}
like(
   $out,
   qr/Users \| $users_count/,
   "Security works"
);

# --read-samples
for my $i (2..7) {
   ok(
      no_diff(
         sub {
            local $ENV{_NO_FALSE_NEGATIVES} = 1;
            print `$env $trunk/bin/$tool --read-samples $trunk/t/pt-mysql-summary/samples/temp00$i  -- --defaults-file=/tmp/12345/my.sandbox.cnf | tail -n+3 | perl -wlnpe 's/Skipping schema analysis.*/Specify --databases or --all-databases to dump and summarize schemas/' | grep -v jemalloc`
         },
         "t/pt-mysql-summary/samples/expected_output_temp00$i.txt",
      ),
      "--read-samples works for t/pt-mysql-summary/temp00$i",
   ) or diag($test_diff);
}

# Test that --help works under sh

my $sh   = `sh   $trunk/bin/$tool --help`;
my $bash = `bash $trunk/bin/$tool --help`;

is(
   $sh,
   $bash,
   "--help works under sh and bash"
);

done_testing;

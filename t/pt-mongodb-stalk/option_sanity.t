#!/usr/bin/env perl

# Option parsing and validation.  Uses the fake commands; no MongoDB server.

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib",
                 "$ENV{PERCONA_TOOLKIT_BRANCH}/t/pt-mongodb-stalk/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More;

use PerconaTest;
use PtMongodbStalkTest;

use_fake_commands();

my ($status, $output);

# --help and the defaults.
($status, $output) = run_capture("bash", $tool, "--help");
is($status, 0, "--help exits 0");
like($output, qr/Command line options:/, "--help lists the options");
like($output, qr/Options and values after processing arguments:/, "--help prints option values");
like($output, qr/--variable\s+connections\.active\n/, "default --variable is connections.active");
like($output, qr/--threshold\s+25\n/, "default --threshold is 25");
like($output, qr/--verbose\s+2\n/, "default --verbose is 2");
like($output, qr/--function\s+status\n/, "default --function is status");

# --version, from the VERSION section of the POD.
($status, $output) = run_capture("bash", $tool, "--version");
is($status, 0, "--version exits 0");
like($output, qr/^pt-mongodb-stalk \d+\.\d+\.\d+\n\z/, "--version prints the version");

# Invalid values.
($status, $output) = run_capture("bash", $tool, "--function", "bogus", "--no-stalk");
is($status, 1, "invalid --function exits 1");
like($output, qr/Invalid --function value: bogus/, "invalid --function is reported");

($status, $output) = run_capture("bash", $tool, "--plugin", "$tmpdir/no-such-plugin", "--no-stalk");
is($status, 1, "--plugin that is not a file exits 1");
like($output, qr/Invalid --plugin value: \S+ is not a file/, "--plugin that is not a file is reported");

($status, $output) = run_capture("bash", $tool, "--bogus");
is($status, 1, "unknown option exits 1");
like($output, qr/Unknown option: --bogus/, "unknown option is reported");

($status, $output) = run_capture("bash", $tool, "--skip-collection", "mongostat,bogus", "--no-stalk");
is($status, 1, "invalid --skip-collection value exits 1");
like($output, qr/Invalid --skip-collection value: bogus\.  Valid values are: currentop,metadata,mongod-log,mongostat,mongotop,replsetgetstatus,serverstatus/,
   "invalid --skip-collection value lists the valid ones");

($status, $output) = run_capture("bash", $tool, "--uri", "http://localhost:27017/", "--no-stalk",
   "--dest", "$tmpdir/bad-uri", "--pid", "$tmpdir/bad-uri.pid");
isnt($status, 0, "--uri that is not mongodb:// fails");
like($output, qr/Invalid --uri: it must start with mongodb:\/\/ or mongodb\+srv:\/\//,
   "--uri that is not mongodb:// is reported");

# Options with uppercase letters cannot be given as --name=value.
($status, $output) = run_capture("bash", $tool, "--authenticationDatabase=admin", "--sslCAFile=/tmp/ca.pem", "--no-stalk");
is($status, 1, "--authenticationDatabase=value exits 1");
like($output, qr/Use '--authenticationDatabase <value>' instead of '--authenticationDatabase=<value>'/,
   "--authenticationDatabase=value prints a specific error");
like($output, qr/Use '--sslCAFile <value>' instead of '--sslCAFile=<value>'/,
   "every uppercase option with = is reported");
unlike($output, qr/Unknown option/, "no generic unknown option error");
unlike($output, qr{/tmp/ca\.pem}, "option values are not printed");

($status, $output) = run_capture("bash", $tool, "--authenticationDatabase", "admin", "--port=27017", "--help");
is($status, 0, "--authenticationDatabase value and lowercase --name=value are accepted") or diag($output);
like($output, qr/--authenticationDatabase\s+admin\n/, "--authenticationDatabase value is set");
like($output, qr/--port\s+27017\n/, "--port=value is set");

# ... nor in a config file.
my $conf = "$tmpdir/pt-mongodb-stalk.conf";
open my $conf_fh, ">", $conf or die "Cannot write $conf: $OS_ERROR";
print {$conf_fh} "port=27017\nauthenticationDatabase = admin\n";
close $conf_fh;
($status, $output) = run_capture("bash", $tool, "--config", $conf, "--help");
is($status, 1, "uppercase option in --config file exits 1");
like($output, qr/\Q$conf\E line 2: option 'authenticationDatabase' cannot be set in a config file/,
   "uppercase option in --config file prints a specific error");

# In the global config files, which all tools read, it is only a warning.
my $home = "$tmpdir/home";
mkdir $home;
open my $global_fh, ">", "$home/.percona-toolkit.conf" or die "Cannot write: $OS_ERROR";
print {$global_fh} "sslCAFile=/tmp/ca.pem\n";
close $global_fh;
{
   local $ENV{HOME} = $home;
   ($status, $output) = run_capture("bash", $tool, "--help");
}
is($status, 0, "uppercase option in the global config file does not stop the tool");
like($output, qr/\.percona-toolkit\.conf line 1: option 'sslCAFile' is ignored in this config file/,
   "uppercase option in the global config file is reported as ignored");

done_testing;

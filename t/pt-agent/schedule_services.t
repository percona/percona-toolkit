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
use JSON;
use File::Temp qw(tempfile tempdir);

use Percona::Test;
use Percona::Test::Mock::AgentLogger;
require "$trunk/bin/pt-agent";

my $crontab = `crontab -l 2>/dev/null`;
if ( $crontab ) {
   plan skip_all => 'Crontab is not empty';
}

Percona::Toolkit->import(qw(have_required_args Dumper));

my $sample = "t/pt-agent/samples";
my $tmpdir = tempdir("/tmp/pt-agent.$PID.XXXXXX", CLEANUP => 1);

my @log;
my $logger = Percona::Test::Mock::AgentLogger->new(log => \@log);
pt_agent::_logger($logger);

# #############################################################################
# Schedule a good crontab.
# #############################################################################

my $run0 = Percona::WebAPI::Resource::Task->new(
   name    => 'query-history',
   number  => '0',
   program => 'pt-query-digest',
   options => '--output json',
   output  => 'spool',
);

my $svc0 = Percona::WebAPI::Resource::Service->new(
   ts             => 100,
   name           => 'query-history',
   run_schedule   => '* 8 * * 1,2,3,4,5',
   spool_schedule => '* 9 * * 1,2,3,4,5',
   tasks          => [ $run0 ],
);

# First add a fake line so we can know that the real, existing
# crontab is used and not clobbered.
my ($fh, $file) = tempfile();
print {$fh} "* 0  *  *  *  date > /dev/null\n";
close $fh or warn "Cannot close $file: $OS_ERROR";
my $output = `crontab $file 2>&1`;

$crontab = `crontab -l 2>&1`;

is(
   $crontab,
   "* 0  *  *  *  date > /dev/null\n",
   "Set other crontab line"
) or diag($output);

unlink $file or warn "Cannot remove $file: $OS_ERROR";

eval {
   $output = output(
      sub {
         pt_agent::schedule_services(
            services => [ $svc0 ],
            lib_dir  => $tmpdir,
         )
      },
      stderr => 1,
   );
};

is(
   $EVAL_ERROR,
   "",
   "No error"
) or diag($output);

$crontab = `crontab -l 2>/dev/null`;

# pt-agent uses $FindBin::Bin/pt-agent for the path to pt-agent,
# which in testing will be $trunk/t/pt-agent/ because that's where
# this file is located.  However, if $FindBin::Bin resovles sym
# links where as $trunk does not, so to make things simple we just
# cut out the full path. 
if ( $crontab ) {
   $crontab =~ s! /.+?/pt-agent --! pt-agent --!g;
}
is(
   $crontab,
   "* 0  *  *  *  date > /dev/null
* 8 * * 1,2,3,4,5 pt-agent --run-service query-history
* 9 * * 1,2,3,4,5 pt-agent --send-data query-history
",
   "schedule_services()"
);

ok(
   -f "$tmpdir/crontab",
   "Wrote crontab to --lib/crontab"
) or diag(`ls -l $tmpdir`);

ok(
   -f "$tmpdir/crontab.err",
   "Write --lib/crontab.err",
) or diag(`ls -l $tmpdir`);

my $err = -f "$tmpdir/crontab.err" ? `cat $tmpdir/crontab.err` : '';
is(
   $err,
   "",
   "No crontab error"
);

system("crontab -r 2>/dev/null");
$crontab = `crontab -l 2>/dev/null`;
is(
   $crontab,
   "",
   "Removed crontab"
);

# #############################################################################
# Handle bad crontab lines.
# #############################################################################

$svc0 = Percona::WebAPI::Resource::Service->new(
   ts             => 100,
   name           => 'query-history',
   run_schedule   => '* * * * Foo',  # "foo":0: bad day-of-week
   spool_schedule => '* 8 * * Mon',
   tasks          => [ $run0 ],
);

eval {
   $output = output(
      sub {
         pt_agent::schedule_services(
            services => [ $svc0 ],
            lib_dir  => $tmpdir,
         ),
      },
      stderr => 1,
      die    => 1,
   );
};

like(
   $EVAL_ERROR,
   qr/Error setting new crontab/,
   "Throws errors"
) or diag($output);

$crontab = `crontab -l 2>/dev/null`;
is(
   $crontab,
   "",
   "Bad schedule_services()"
);

ok(
   -f "$tmpdir/crontab",
   "Wrote crontab to --lib/crontab"
) or diag(`ls -l $tmpdir`);

ok(
   -f "$tmpdir/crontab.err",
   "Write --lib/crontab.err",
) or diag(`ls -l $tmpdir`);

$err = -f "$tmpdir/crontab.err" ? `cat $tmpdir/crontab.err` : '';
like(
   $err,
   qr/bad/,
   "Crontab error"
);

system("crontab -r 2>/dev/null");
$crontab = `crontab -l 2>/dev/null`;
is(
   $crontab,
   "",
   "Removed crontab"
);


# #############################################################################
# Done.
# #############################################################################
done_testing;

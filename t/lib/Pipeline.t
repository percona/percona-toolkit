#!/usr/bin/perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More tests => 11;

use Time::HiRes qw(usleep);

use PerconaTest;
use Pipeline;

my $output  = '';
my $oktorun = 1;
my %args = (
   oktorun => \$oktorun,
);

# #############################################################################
# A simple run stopped by a proc returning and exit status.
# #############################################################################

my $pipeline = new Pipeline();
$pipeline->add(
   name    => 'proc1',
   process => sub {
      print "proc1";
      $oktorun = 0;
      return;
   },
);

$output = output(
   sub { $pipeline->execute(%args); },
);

is(
   $output,
   "proc1",
   "Pipeline ran"
);

# #############################################################################
# Restarting the pipeline.
# #############################################################################

$oktorun = 1;
my @exit = (undef, 1);

$pipeline = new Pipeline();
$pipeline->add(
   name    => 'proc1',
   process => sub {
      print "proc1";
      return 1;
   },
);
$pipeline->add(
   name    => 'proc2',
   process => sub {
      print "proc2";
      return shift @exit;
   },
);
$pipeline->add(
   name    => 'proc3',
   process => sub {
      print "proc3";
      $oktorun = 0;
      return;
   },
);

$output = output(
   sub { $pipeline->execute(%args); },
);

is(
   $output,
   "proc1proc2proc1proc2proc3",
   "Pipeline restarted"
);

# #############################################################################
# oktorun to control the loop.
# #############################################################################

$oktorun = 0;
$pipeline = new Pipeline();
$pipeline->add(
   name    => 'proc1',
   process => sub {
      print "proc1";
      return 0;
   },
);

$output = output(
   sub { $pipeline->execute(%args); },
);

is(
   $output,
   "",
   "oktorun prevented pipeline from running"
);

# #############################################################################
# Run multiple procs.
# #############################################################################

my $pargs = {};
$args{pipeline_data} = $pargs;

$oktorun  = 1;
$pipeline = new Pipeline();
$pipeline->add(
   name    => 'proc1',
   process => sub {
      my ( $args ) = @_;
      $args->{foo} .= "foo";
      print "proc1";
      return $args;
   },
);
$pipeline->add(
   name    => 'proc2',
   process => sub {
      my ( $args ) = @_;
      $args->{foo} .= "bar";
      print "proc2";
      $oktorun = 0;
      return;
   },
);

$output = output(
   sub { $pipeline->execute(%args); },
);

is(
   $output,
   "proc1proc2",
   "Multiple procs ran"
);

is(
   $pargs->{foo},
   "foobar",
   "Pipeline passed data hashref around"
);

# #############################################################################
# Instrumentation.
# #############################################################################
$oktorun = 1;
$pipeline = new Pipeline(instrument => 1);
$pipeline->add(
   name    => 'proc1',
   process => sub {
      usleep(500000);
      return 1;
   },
);
$pipeline->add(
   name    => 'proc2',
   process => sub {
      $oktorun = 0;
   },
);

$pipeline->execute(%args);

my $inst = $pipeline->instrumentation();
ok(
   $inst->{proc1}->{calls} = 1 && $inst->{proc2}->{calls} = 1,
   "Instrumentation counted calls"
);

ok(
   $inst->{proc1}->{time} > 0.4 && $inst->{proc1}->{time} < 0.6,
   "Instrumentation timed procs"
);

# #############################################################################
# Reset the previous ^ pipeline.
# #############################################################################
$pipeline->reset();
$inst  = $pipeline->instrumentation();
is(
   $inst->{proc1}->{calls},
   0,
   "Reset instrumentation"
);


# #############################################################################
# Continue on error.
# #############################################################################
$oktorun  = 1;
$pipeline = new Pipeline(continue_on_error=>1);

my @called = ();
my @die    = qw(1 0);
$pipeline->add(
   name    => 'proc1',
   process => sub {
      my ( $args ) = @_;
      push @called, 'proc1';
      die "I'm an error" if shift @die;
      return $args;
   },
);
$pipeline->add(
   name    => 'proc2',
   process => sub {
      push @called, 'proc2';
      $oktorun = 0;
      return;
   },
);

$output = output(
   sub { $pipeline->execute(%args); },
   stderr => 1,
);

is_deeply(
   \@called,
   [qw(proc1 proc1 proc2)],
   "Continues on error"
);

# Override global for critical procs that must kill the pipeline if they die.
$oktorun  = 1;
$pipeline = new Pipeline(continue_on_error=>1);

@called = ();
$pipeline->add(
   name    => 'proc1',
   process => sub {
      my ( $args ) = @_;
      push @called, 'proc1';
      $oktorun = 0 if @called > 8;
      return $args;
   },
);
$pipeline->add(
   retry_on_error => 2,
   name           => 'proc2',
   process        => sub {
      push @called, 'proc2';
      die;
   },
);

$output = output(
   sub {$pipeline->execute(%args); },
   stderr => 1,
);

is_deeply(
   \@called,
   [qw(proc1 proc2),  # first attempt
    qw(proc1 proc2),  # retry 1/2
    qw(proc1 proc2)], # retry 2/2
   "Retry proc"
) or diag($output);

# #############################################################################
# Done.
# #############################################################################
{
   local *STDERR;
   open STDERR, '>', \$output;
   $pipeline->_d('Complete test coverage');
}
like(
   $output,
   qr/Complete test coverage/,
   '_d() works'
);
exit;

#!/usr/bin/env perl

# This script is used by Daemon.t because that test script
# cannot daemonize itself.

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);

use constant PTDEBUG    => $ENV{PTDEBUG}    || 0;
use constant PTDEVDEBUG => $ENV{PTDEVDEBUG} || 0;

use Time::HiRes qw(sleep);

use Daemon;
use OptionParser;
use PerconaTest;

my $o = new OptionParser(file => "$trunk/t/lib/samples/daemonizes.pl");
$o->get_specs();
$o->get_opts();

my ($sleep_time) = shift @ARGV;
if ( !defined $sleep_time ) {
   $o->save_error('No SLEEP_TIME specified');
}

$o->usage_or_errors();

my $daemon = Daemon->new(
   daemonize => $o->get('daemonize'),
   pid_file  => $o->get('pid'),
   log_file  => $o->get('log'),
);

$daemon->run();
PTDEVDEBUG && PerconaTest::_d('daemonized');

print "STDOUT\n";
print STDERR "STDERR\n";

PTDEVDEBUG && PerconaTest::_d('daemon sleep', $sleep_time);
sleep $sleep_time;

PTDEVDEBUG && PerconaTest::_d('daemon done');
exit;

# ############################################################################
# Documentation.
# ############################################################################

=pod

=head1 SYNOPSIS

Usage: daemonizes.pl SLEEP_TIME

daemonizes.pl daemonizes, prints to STDOUT and STDERR, sleeps and exits.

=head1 OPTIONS

This tool accepts additional command-line arguments.  Refer to the
L<"SYNOPSIS"> and usage information for details.

=over

=item --daemonize

Fork to background and detach (POSIX only).  This probably doesn't work on
Microsoft Windows.

=item --help

Show help and exit.

=item --log

type: string

Print all output to this file when daemonized.

=item --pid

type: string 

Create the given PID file when daemonized.

=back

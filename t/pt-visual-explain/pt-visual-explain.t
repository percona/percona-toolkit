#!/usr/bin/env perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More tests => 4;

use PerconaTest;
require "$trunk/bin/pt-visual-explain";

sub run {
   my $output = '';
   open OUTPUT, '>', \$output
      or die 'Cannot open output to variable';
   select OUTPUT;
   pt_visual_explain::main(@_);
   select STDOUT;
   close $output;
   return $output;
}

like(
   run("$trunk/t/pt-visual-explain/samples/simple_union.sql"),
   qr/\+\- UNION/,
   'Read optional input file (issue 394)',
);

like(
   run("$trunk/t/pt-visual-explain/samples/simple_union.sql", qw(--format dump)),
   qr/\$VAR1 = {/,
   '--format dump (issue 393)'
);

# #########################################################################
# Issue 391: Add --pid option to all scripts
# #########################################################################
`touch /tmp/mk-script.pid`;
my $output = `$trunk/bin/pt-visual-explain $trunk/t/pt-visual-explain/samples/simple_union.sql --format dump --pid /tmp/mk-script.pid 2>&1`;
like(
   $output,
   qr{PID file /tmp/mk-script.pid already exists},
   'Dies if PID file already exists (issue 391)'
);
`rm -rf /tmp/mk-script.pid`;


# ############################################################################
# Bug #823394: --version doesn't work 
# ############################################################################
$output = `$trunk/bin/pt-visual-explain --version 2>&1`;
like(
   $output,
   qr/^pt-visual-explain \d\.\d\.\d+/m,
   '--version works (bug 823394)'
);

# #############################################################################
# Done.
# #############################################################################
exit;

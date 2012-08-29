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
shift @INC;  # These two shifts are required for tools that use base and
shift @INC;  # derived classes.  See mk-query-digest/t/101_slowlog_analyses.t
require "$trunk/bin/pt-variable-advisor";

# #############################################################################
# SHOW VARIABLES from text files.
# #############################################################################
my @args   = qw();
my $sample = "$trunk/t/lib/samples/show-variables/";

ok(
   no_diff(
      sub { pt_variable_advisor::main(@args,
         qw(--source-of-variables), "$sample/vars001.txt") },
      "t/pt-variable-advisor/samples/vars001.txt",
   ),
   "vars001.txt"
);

ok(
   no_diff(
      sub { pt_variable_advisor::main(@args,
         qw(--source-of-variables), "$sample/vars002.txt") },
      "t/pt-variable-advisor/samples/vars002.txt",
   ),
   "vars002.txt"
);

ok(
   no_diff(
      sub { pt_variable_advisor::main(@args,
         qw(-v --source-of-variables), "$sample/vars001.txt") },
      "t/pt-variable-advisor/samples/vars001-verbose.txt",
   ),
   "vars001.txt --verbose"
);

ok(
   no_diff(
      sub { pt_variable_advisor::main(@args,
         qw(-v -v --source-of-variables), "$sample/vars001.txt") },
      "t/pt-variable-advisor/samples/vars001-verbose-verbose.txt",
   ),
   "vars001.txt --verbose --verbose"
);

ok(
   no_diff(
      sub { pt_variable_advisor::main(@args,
         qw(--source-of-variables), "$sample/vars001.txt",
         qw(--ignore-rules), "sync_binlog,myisam_recover_options") },
      "t/pt-variable-advisor/samples/vars001-ignore-rules.txt",
   ),
   "--ignore-rules"
);

my ($output) = full_output(sub {
    pt_variable_advisor::main(@args,
        '--source-of-variables', "$sample/vars-baron-002.txt"
)});

like(
   $output,
   qr/\Qdual-master or ring replication configuration?\E$/sm,
   "Sentences are delimited by . or ?"
);

# #############################################################################
# Done.
# #############################################################################
done_testing;

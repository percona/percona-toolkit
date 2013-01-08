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
use File::Temp qw(tempfile);

use Percona::Test;
require "$trunk/bin/pt-agent";

Percona::Toolkit->import(qw(have_required_args Dumper));

my @output_files = ();

sub test_replace {
   my (%args) = @_;
   have_required_args(\%args, qw(
      cmd
      expect
   )) or die;
   my $cmd    = $args{cmd};
   my $expect = $args{expect};

   my $new_cmd = pt_agent::replace_special_vars(
      cmd          => $cmd,
      output_files => \@output_files,
   );

   is(
      $new_cmd,
      $expect,
      $cmd,
   );
};

@output_files = qw(zero one two);
test_replace(
   cmd    => "pt-query-digest __RUN_0_OUTPUT__",
   expect => "pt-query-digest zero",
);

# #############################################################################
# Done.
# #############################################################################
done_testing;

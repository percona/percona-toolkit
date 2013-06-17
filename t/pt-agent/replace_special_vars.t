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
use Percona::Test::Mock::AgentLogger;
require "$trunk/bin/pt-agent";

Percona::Toolkit->import(qw(have_required_args Dumper));

my @log;
my $logger = Percona::Test::Mock::AgentLogger->new(log => \@log);
pt_agent::_logger($logger);

my @output_files = ();
my $store        = {};

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
      service      => 'service-name',
      lib_dir      => '/var/lib/pt-agent',
      meta_dir     => '/var/lib/pt-agent/meta',
      stage_dir    => '/var/spool/.tmp',
      spool_dir    => '/var/spool',
      bin_dir      => $trunk,
      ts           => '123',
      store        => $store,
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

$store->{slow_query_log_file} = 'slow.log';
test_replace(
   cmd    => "echo '__STORE_slow_query_log_file__' > /var/spool/pt-agent/.tmp/1371269644.rotate-slow-query-log-all-5.1.slow_query_log_file",
   expect => "echo 'slow.log' > /var/spool/pt-agent/.tmp/1371269644.rotate-slow-query-log-all-5.1.slow_query_log_file",
);

# #############################################################################
# Done.
# #############################################################################
done_testing;

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
use File::Temp qw();

use PerconaTest;
require "$trunk/bin/pt-diskstats";

# Re-open STDIN to /dev/null before the tieing magic, to avoid
# a bug in older Perls.
open STDIN, "<", "/dev/null";

# pt-diskstats is an interactive-only tool.  It waits for user input
# (i.e. menu commands) via STDIN.  So we cannot just run it with input,
# get ouput, then test that output.  We have to tie STDIN to these subs
# so that we can fake sending pt-diskstats menu commands via STDIN.
# All we do is send 'q', the command to quit.  See the note in the bottom
# of this file about *DATA. Please don't close it.
my $called_seek_on_handle = 0;
{
   $TestInteractive::first = 1;
   sub TestInteractive::TIEHANDLE {
      my ($class, @cmds) = @_;
      push @cmds, "q";
      return bless \@cmds, $class;
   }

   sub TestInteractive::FILENO {
      return fileno(*DATA);
   }

   sub TestInteractive::READLINE {
      my ($self) = @_;
      my $cmd = shift @$self;
      return unless $cmd;
      print $cmd if $cmd =~ /\n/ && !-t STDOUT;
      if ($cmd =~ /^TS/) {
         if ( $TestInteractive::first ) {
            $TestInteractive::first = 0;
         }
         else {
            splice @$self, 1, 0, (undef) x 50;
         }
      }
      return $cmd;
   }

   sub TestInteractive::EOF {
      my ($self) = @_;
      return @$self ? undef : 1;
   }

   sub TestInteractive::CLOSE { 1 }

   sub TestInteractive::TELL {}

   sub TestInteractive::SEEK {
      $called_seek_on_handle++;
   }
}

sub test_diskstats_file {
   my (%args)     = @_;
   my $file       = "$trunk/t/pt-diskstats/samples/$args{file}";
   my @commands   = @{ $args{commands} || [qw( q )] };
   my $print_cmds = join "][",
                        map {
                           ( my $x = $_ ) =~ s/\n/\\n/g;
                           $x
                        } @commands;
   my @options    = $args{options}
                  ? @{ $args{options} }
                  : (
                        '--show-inactive',
                        '--headers', '',
                        '--columns-regex','cnc|rt|mb|busy|prg',
                    );
   die "$file does not exist" unless -f $file;
   foreach my $groupby ( qw(all disk sample) ) {
      my $expect_file = "${groupby}_int_$args{file}";
      ok(
         no_diff(
            sub {
               tie local *STDIN, TestInteractive => @commands;
               local $PerconaTest::DONT_RESTORE_STDIN =
                     $PerconaTest::DONT_RESTORE_STDIN = 1;
               pt_diskstats::main(
                  @options,
                  '--group-by', $groupby,
                  $file);
            },
            "t/pt-diskstats/expected/$expect_file",
         ),
         "$args{file} --group-by $groupby, commands: [$print_cmds]"
      ) or diag($expect_file, $test_diff);
   }
}

foreach my $file ( map "diskstats-00$_.txt", 1..5 ) {
   test_diskstats_file(file => $file);
}

test_diskstats_file(
   file => "switch_to_sample.txt",
   commands => [ qw( S q ) ]
);

test_diskstats_file(
   file     => "commands.txt",
   commands => [ "i", "/", "cciss\n", "q" ]
);

test_diskstats_file(
   file     => "small.txt",
   options  => [ '--headers', '', '--columns-regex','time', ],
);

# ###########################################################################
# --group-by sample + --devices-regex show the wrong device name
# https://bugs.launchpad.net/percona-toolkit/+bug/1035311
# ###########################################################################
test_diskstats_file(
   file     => "bug-1035311.txt",
   commands => [ "S", "/", 'xvdb1', "q" ],
   options  => [ '--headers', ''],
);

# ###########################################################################
# --save-samples and --iterations
# ###########################################################################

my (undef, $tempfile) = File::Temp::tempfile(
   "/tmp/pt-diskstats.test.XXXXXX",
   OPEN => 0,
);

my $iterations = 2;
my $out = output( sub {
   pt_diskstats::main(
      "--group-by"      => "all",
      "--columns-regex" => "cnc|rt|mb|busy|prg",
      "--save-samples"  => $tempfile,
      "--iterations"    => $iterations,
      "--show-inactive",
   );
});

open my $samples_fh, "<", $tempfile
   or die "Cannot open $tempfile: $OS_ERROR";
my $count;
while (my $line = <$samples_fh>) {
   $count++ if $line =~ /^TS/;
}
close $samples_fh or diag($EVAL_ERROR);
unlink $tempfile or diag($EVAL_ERROR);
ok(
   ($count == $iterations) || ($count == $iterations+1),
   "--save-samples and --iterations work"
);

# ###########################################################################
# Done.
# ###########################################################################
done_testing;

__DATA__
Leave this here!
We tie STDIN during the tests, and fake the fileno by giving it *DATA's result;
These lines here make Perl leave *DATA open.

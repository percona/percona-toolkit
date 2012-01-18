#!/usr/bin/env perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More tests => 22;

use File::Temp ();

use PerconaTest;
require "$trunk/bin/pt-diskstats";

# pt-diskstats is an interactive-only tool.  It waits for user input
# (i.e. menu commands) via STDIN.  So we cannot just run it with input,
# get ouput, then test that output.  We have to tie STDIN to these subs
# so that we can fake sending pt-diskstats menu commands via STDIN.
# All we do is send 'q', the command to quit.  See the note in the bottom
# of this file about *DATA. Please don't close it.
{
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
   print $cmd if $cmd =~ /\n/;
   return $cmd;
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
   die "$file does not exist" unless -f $file;
   foreach my $groupby ( qw(all disk sample) ) {
      ok(
         no_diff(
            sub {
               tie local *STDIN, TestInteractive => @commands;
               pt_diskstats::main(
                  '--show-inactive',
                  '--no-automatic-headers',
                  '--group-by', $groupby,
                  '--columns-regex','cnc|rt|mb|busy|prg',
                  $file);
            },
            "t/pt-diskstats/expected/${groupby}_int_$args{file}",
            keep_output=>1,
         ),
         "$args{file} --group-by $groupby, commands: [$print_cmds]"
      );
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

# ###########################################################################
# --save-samples and --iterations
# ###########################################################################

my ($fh, $tempfile) = File::Temp::tempfile( "pt-diskstats.test.$PID.XXXXXX", OPEN => 0);

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

is(
   $count,
   $iterations,
   "--save-samples and --iterations work"
);

1 while unlink $tempfile;

# ###########################################################################
# Done.
# ###########################################################################
exit;

__DATA__
Leave this here!
We tie STDIN during the tests, and fake the fileno by giving it *DATA's result;
These lines here make Perl leave *DATA open.

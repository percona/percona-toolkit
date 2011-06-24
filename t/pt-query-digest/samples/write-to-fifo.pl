#!/usr/bin/env perl

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);

my ($fifo, $t) = @ARGV;

open my $fh, '>', $fifo or die $OS_ERROR;
print $fh "I'm a little teapot short and stout...\n";
sleep $t;

exit;

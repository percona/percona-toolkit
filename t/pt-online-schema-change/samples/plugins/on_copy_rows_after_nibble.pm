package pt_online_schema_change_plugin;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

sub new {
   my ($class, %args) = @_;
   my $self = { %args };
   return bless $self, $class;
}

sub on_copy_rows_after_nibble {
   my ($self, %args) = @_;
   my $tbl = $args{tbl};
   print "PLUGIN on_copy_rows_after_nibble\n";
   print "Chunk size: $tbl->{chunk_size}\n";
   print "Nibble time: $tbl->{nibble_time}\n";
   print "Rows count: $tbl->{row_cnt}\n";
   print "Current average rate: $tbl->{rate}->{avg_rate}\n";
}

1;

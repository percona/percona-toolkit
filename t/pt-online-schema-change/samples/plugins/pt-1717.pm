package pt_online_schema_change_plugin;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;
use Data::Dumper;

sub new {
   my ($class, %args) = @_;
   my $self = { %args };
   return bless $self, $class;
}

sub on_copy_rows_after_nibble {
   my ($self, %args) = @_;
   my $tbl = $args{tbl};
   print "Chunk: $tbl->{results}->{n_chunks}\n";
}

1;

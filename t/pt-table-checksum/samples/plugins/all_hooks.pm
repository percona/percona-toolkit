package pt_table_checksum_plugin;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

sub new {
   my ($class, %args) = @_;
   my $self = { %args };
   return bless $self, $class;
}

sub init {
   my ($self, %args) = @_;
   print "PLUGIN init\n";
}
 
sub before_replicate_check {
   my ($self, %args) = @_;
   print "PLUGIN before_replicate_check\n";
}
 
sub after_replicate_check {
   my ($self, %args) = @_;
   print "PLUGIN after_replicate_check\n";
}
 
sub get_slave_lag {
   my ($self, %args) = @_;
   print "PLUGIN get_slave_lag\n";
   return sub { return 0; };
}
 
sub before_checksum_table {
   my ($self, %args) = @_;
   print "PLUGIN before_checksum_table\n";
}

sub after_checksum_table {
   my ($self, %args) = @_;
   print "PLUGIN after_checksum_table\n";
}

1;

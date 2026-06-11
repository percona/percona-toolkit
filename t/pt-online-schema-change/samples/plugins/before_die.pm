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

sub before_die {
   my ($self, %args) = @_;
   print "PLUGIN before_die\n";
   print "Exit status: $args{exit_status}\n";
}

1;

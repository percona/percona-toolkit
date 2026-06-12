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

sub after_create_new_table {
   my ($self, %args) = @_;

   print "PLUGIN after_create_new_table\n";

   my $dbh     = $self->{aux_cxn}->dbh;
   my $new_tbl = $args{new_tbl}->{name};

   # Remove PRIMARY KEY, so pt-osc fails with an error and handles 
   # it in the _die call
   $dbh->do("ALTER TABLE ${new_tbl} MODIFY COLUMN id INT NOT NULL, DROP PRIMARY KEY");
}

1;

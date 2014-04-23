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

sub init {
   my ($self, %args) = @_;
   print "PLUGIN init\n";
}
 
sub before_create_new_table {
   my ($self, %args) = @_;
   print "PLUGIN before_create_new_table\n";
}
 
sub after_create_new_table {
   my ($self, %args) = @_;
   print "PLUGIN after_create_new_table\n";
}
 
sub before_alter_new_table {
   my ($self, %args) = @_;
   print "PLUGIN before_alter_new_table\n";
}
 
sub after_alter_new_table {
   my ($self, %args) = @_;
   print "PLUGIN after_alter_new_table\n";
}

sub before_create_triggers {
   my ($self, %args) = @_;
   print "PLUGIN before_create_triggers\n";
}
 
sub after_create_triggers {
   my ($self, %args) = @_;
   print "PLUGIN after_create_triggers\n";
}
 
sub before_copy_rows {
   my ($self, %args) = @_;
   print "PLUGIN before_copy_rows\n";
}
 
sub after_copy_rows {
   my ($self, %args) = @_;
   print "PLUGIN after_copy_rows\n";
}
 
sub before_swap_tables {
   my ($self, %args) = @_;
   print "PLUGIN before_swap_tables\n";
}
 
sub after_swap_tables {
   my ($self, %args) = @_;
   print "PLUGIN after_swap_tables\n";
}
 
sub before_update_foreign_keys {
   my ($self, %args) = @_;
   print "PLUGIN before_update_foreign_keys\n";
}
 
sub after_update_foreign_keys {
   my ($self, %args) = @_;
   print "PLUGIN after_update_foreign_keys\n";
}
 
sub before_drop_old_table {
   my ($self, %args) = @_;
   print "PLUGIN before_drop_old_table\n";
}
 
sub after_drop_old_table {
   my ($self, %args) = @_;
   print "PLUGIN after_drop_old_table\n";
}
 
sub before_drop_triggers {
   my ($self, %args) = @_;
   print "PLUGIN before_drop_triggers\n";
}
 
sub before_exit {
   my ($self, %args) = @_;
   print "PLUGIN before_exit\n";
}

sub get_slave_lag {
   my ($self, %args) = @_;
   print "PLUGIN get_slave_lag\n";

   return sub { return 0; };
}

1;

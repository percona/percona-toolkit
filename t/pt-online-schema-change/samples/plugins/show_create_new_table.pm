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

sub after_create_new_table {
   my ($self, %args) = @_;
   my $new_tbl = $args{new_tbl};
   my $dbh     = $self->{cxn}->dbh;
   my $row = $dbh->selectrow_arrayref("SHOW CREATE TABLE $new_tbl->{name}");
   warn "after_create_new_table: $row->[1]\n\n";
}
 
sub after_alter_new_table {
   my ($self, %args) = @_;
   my $new_tbl = $args{new_tbl};
   my $dbh     = $self->{cxn}->dbh;
   my $row = $dbh->selectrow_arrayref("SHOW CREATE TABLE $new_tbl->{name}");
   warn "after_alter_new_table: $row->[1]\n\n";
}

1;

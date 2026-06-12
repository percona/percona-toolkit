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

sub on_copy_rows_after_nibble {
   my ($self, %args) = @_;
   my $tbl = $args{tbl};
   print "PLUGIN on_copy_rows_after_nibble\n";
   if ($tbl->{row_cnt} > 1000) {
      my $dbh      = $self->{aux_cxn}->dbh;

      # Run invalid query to get error
      $dbh->do("SELECT * FRO " . $tbl->{name});
   }
}

1;

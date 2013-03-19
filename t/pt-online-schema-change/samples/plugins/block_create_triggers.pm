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
   print "PLUGIN: init()\n";
   $self->{orig_tbl} = $args{orig_tbl};
}

sub before_create_triggers {
   my ($self, %args) = @_;
   print "PLUGIN: before_create_triggers()\n";

   my $dbh      = $self->{aux_cxn}->dbh;
   my $orig_tbl = $self->{orig_tbl};

   # Start a trx and get a metadata lock on the table being altered.
   $dbh->do('SET autocommit=0');
   $dbh->{AutoCommit} = 0;
   $dbh->do("START TRANSACTION");
   $dbh->do("SELECT * FROM " . $orig_tbl->{name});

   return;
}

sub after_create_triggers {
   my ($self, %args) = @_;
   print "PLUGIN: after_create_triggers()\n";

   my $dbh = $self->{aux_cxn}->dbh;

   # Commit the trx to release the metadata lock.
   $dbh->commit();
}

1;

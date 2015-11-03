package pt_online_schema_change_plugin;

use strict;
use warnings;

sub new {
   my ( $class, %args ) = @_;
   my $self = {};
   return bless $self, $class;
}

sub before_swap_tables {
   my ($self, %args) = @_;
   print `mysql -e "select * From mysql.innodb_index_stats where database_name='test'"`;
   print `mysql -e "select * From mysql.innodb_table_stats where database_name='test'"`;
   sleep 12;
   print `mysql -e "select * From mysql.innodb_index_stats where database_name='test'"`;
   print `mysql -e "select * From mysql.innodb_table_stats where database_name='test'"`;
}

1;

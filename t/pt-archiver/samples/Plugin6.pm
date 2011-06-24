package Plugin6;
use strict;
use warnings FATAL => 'all';

sub new {
   my ( $class, %args ) = @_;
   return bless(\%args, $class);
}

sub is_archivable {1} # Always yes

sub before_delete {} # Take no action

sub before_insert { }

# Move rows to table_odd or table_even
sub custom_sth {
   my ( $self, %args ) = @_;
   my $parity = ( $args{row}->[0] % 2 == 0 ) ? 'even' : 'odd';
   my $sth;
   if ( $self->{sth_cache}->{$parity} ) {
      $sth = $self->{sth_cache}->{$parity};
   }
   else {
      ( my $sql = $args{sql} ) =~ s/$self->{tbl}/table_$parity/;
      $self->{dbh}->do(
         "CREATE TABLE IF NOT EXISTS $self->{db}.table_$parity LIKE $self->{db}.$self->{tbl}");
      $sth = $self->{dbh}->prepare($sql);
      $self->{sth_cache}->{$parity} = $sth;
   }
   return $sth;
}

sub before_begin {} # Take no action
sub after_finish {} # Take no action

1;

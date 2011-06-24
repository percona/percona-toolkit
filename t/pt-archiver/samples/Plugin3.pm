package Plugin3;

sub new {
   my ( $class, %args ) = @_;
   $args{sth} = $args{dbh}->prepare(
      "INSERT INTO test.table_2 values(?,?,?,?)");
   return bless(\%args, $class);
}

sub is_archivable {1} # Always yes

sub before_delete {
   my ( $self, %args ) = @_;
   $self->{sth}->execute(@{$args{row}});
}

sub before_insert {} # Take no action
sub before_begin {} # Take no action
sub after_finish {} # Take no action

1;


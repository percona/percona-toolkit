package Plugin4;

sub new {
   my ( $class, %args ) = @_;
   $args{sth} = $args{dbh}->prepare(
      "INSERT INTO test.table_9 values(?,?,?)
      ON DUPLICATE KEY UPDATE b=b+1, c=c+values(c)
      ");
   return bless(\%args, $class);
}

sub is_archivable {1} # Always yes

sub before_delete {} # Take no action

sub before_insert {
   my ( $self, %args ) = @_;
   $self->{sth}->execute(@{$args{row}});
}

sub custom_sth {} # no action
sub before_begin {} # Take no action
sub after_finish {} # Take no action

1;


package Plugin7;

sub new {
   my ( $class, %args ) = @_;
   return bless(\%args, $class);
}

sub statistics {
   my ( $self, $stats, $start ) = @_;
   $self->{src}->{dbh}->do(
      "insert into test.stat_test(a) values($stats->{DELETE})");
}

1;

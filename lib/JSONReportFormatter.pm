{
package JSONReportFormatter;
use Mo;
use JSON;

use Transformers qw(make_checksum);

use constant PTDEBUG => $ENV{PTDEBUG} || 0;

extends qw(QueryReportFormatter);

has history_metrics => (
   is       => 'ro',
   isa      => 'HashRef',
);

sub BUILDARGS {
   my $class     = shift;
   my %orig_args = @_;
   my $args      = $class->SUPER::BUILDARGS(@_);

   my $o         = $orig_args{OptionParser};

   my $sql = $o->read_para_after(
      __FILE__, qr/MAGIC_create_review_history/);

   my $pat = $o->read_para_after(__FILE__, qr/MAGIC_history_cols/);
   $pat = qr/\ {3}(\w+?)_($pat)\s+/;

   my %metrics;
   foreach my $sql_line (split /\n/, $sql) {
      my ( $attr, $metric ) = $sql_line =~ $pat;
      next unless $attr && $metric;

      $attr = ucfirst $attr if $attr =~ m/_/;
      $attr = 'Filesort' if $attr eq 'filesort';

      $attr =~ s/^Qc_hit/QC_Hit/;  # Qc_hit is really QC_Hit
      $attr =~ s/^Innodb/InnoDB/g; # Innodb is really InnoDB
      $attr =~ s/_io_/_IO_/g;      # io is really IO

      $metrics{$attr}{$metric} = 1;
   }

   $args->{history_metrics} = \%metrics;

   return $args;
}

override [qw(rusage date hostname files header profile prepared)] => sub {
   return;
};

override event_report => sub {
   my ($self, %args) = @_;
   return $self->event_report_values(%args);
};

override query_report => sub {
   my ($self, %args) = @_;
   foreach my $arg ( qw(ea worst orderby groupby) ) {
      die "I need a $arg argument" unless defined $arg;
   }

   my $ea    = $args{ea};
   my $worst = $args{worst};

   my $history_metrics = $self->history_metrics;
   my @attribs = grep { $history_metrics->{$_} } @{$ea->get_attributes()};

   my @queries;
   foreach my $worst_info ( @$worst ) {
      my $item        = $worst_info->[0];
      my $stats       = $ea->results->{classes}->{$item};
      my $sample      = $ea->results->{samples}->{$item};

      my %metrics;
      foreach my $attrib ( @attribs ) {
         $metrics{$attrib} = $ea->metrics(
            attrib => $attrib,
            where  => $item,
         );

         my $needed_metrics = $history_metrics->{$attrib};
         for my $key ( keys %{$metrics{$attrib}} ) {
            delete $metrics{$attrib}{$key}
               unless $needed_metrics->{$key};
         }
      }

      push @queries, {
         sample   => $sample,
         checksum => make_checksum($item),
         %metrics
      };
   }

   return encode_json(\@queries) . "\n";
};

1;
}

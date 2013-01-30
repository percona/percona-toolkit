{
package JSONReportFormatter;
use Mo;
use JSON ();

use List::Util qw(sum);

use Transformers qw(make_checksum parse_timestamp);

use constant PTDEBUG => $ENV{PTDEBUG} || 0;

our $pretty_json = undef;
our $sorted_json = undef;

extends qw(QueryReportFormatter);

has _json => (
   is       => 'ro',
   init_arg => undef,
   builder  => '_build_json',
   handles  => { encode_json => 'encode' },
);

sub _build_json {
   return JSON->new->utf8->pretty($pretty_json)->canonical($sorted_json);
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

   my @attribs = @{$ea->get_attributes()};
   
   my @queries;
   foreach my $worst_info ( @$worst ) {
      my $item   = $worst_info->[0];
      my $stats  = $ea->results->{classes}->{$item};
      my $sample = $ea->results->{samples}->{$item};

      my $all_log_pos = $ea->{result_classes}->{$item}->{pos_in_log}->{all};
      my $times_seen  = sum values %$all_log_pos;
      
      my %class = (
         sample      => $sample->{arg},
         fingerprint => $item,
         checksum    => make_checksum($item),
         cnt         => $times_seen,
      );
      
      my %metrics;
      foreach my $attrib ( @attribs ) {
         $metrics{$attrib} = $ea->metrics(
            attrib => $attrib,
            where  => $item,
         );
      }

      foreach my $attrib ( keys %metrics ) {
         if ( ! grep { $_ } values %{$metrics{$attrib}} ) {
            delete $metrics{$attrib};
            next;
         }

         if ($attrib eq 'ts') {
            my $ts = delete $metrics{ts};
            foreach my $thing ( qw(min max) ) {
               next unless defined $ts && defined $ts->{$thing};
               $ts->{$thing} = parse_timestamp($ts->{$thing});
            }
            $class{ts_min} = $ts->{min};
            $class{ts_max} = $ts->{max};
         }
         elsif ( ($ea->{type_for}->{$attrib} || '') eq 'num' ) {
            # Avoid scientific notation in the metrics by forcing it to use
            # six decimal places.
            for my $value ( values %{$metrics{$attrib}} ) {
               next unless $value;
               $value = sprintf '%.6f', $value;
            }
            # ..except for the percentage, which only needs two
            if ( my $pct = $metrics{$attrib}->{pct} ) {
               $metrics{$attrib}->{pct} = sprintf('%.2f', $pct);
            }
         }
      }
      push @queries, {
         class       => \%class,
         attributes  => \%metrics,
      };
   }

   return $self->encode_json(\@queries) . "\n";
};

1;
}

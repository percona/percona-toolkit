{
package JSONReportFormatter;
use Mo;
use JSON;

use constant PTDEBUG => $ENV{PTDEBUG} || 0;

extends qw(QueryReportFormatter);

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
   my $ea      = $args{ea};
   my $groupby = $args{groupby};
   my $worst   = $args{worst};

   my $q   = $self->Quoter;
   my $qv  = $self->{QueryReview};
   my $qr  = $self->{QueryRewriter};

   my $query_report_vals = $self->query_report_values(%args);

   # Sort the attributes, removing any hidden attributes.
   my $attribs = $self->sort_attribs(
      ($args{select} ? $args{select} : $ea->get_attributes()),
         $ea,
   );

   ITEM:
   foreach my $vals ( @$query_report_vals ) {
      my $item       = $vals->{item};
      my $samp_query = $vals->{samp_query};
      # ###############################################################
      # Print the standard query analysis report.
      # ###############################################################
      $vals->{event_report} = $self->event_report(
         %args,
         item    => $item,
         sample  => $ea->results->{samples}->{$item},
         rank    => $vals->{rank},
         reason  => $vals->{reason},
         attribs => $attribs,
         db      => $vals->{default_db},
      );

      if ( $groupby eq 'fingerprint' ) {
         if ( $item =~ m/^(?:[\(\s]*select|insert|replace)/ ) {
            if ( $item !~ m/^(?:insert|replace)/ ) { # No EXPLAIN
               $vals->{for_explain} = "EXPLAIN /*!50100 PARTITIONS*/\n$samp_query\\G\n";
               $vals->{explain_report} = $self->explain_report($samp_query, $vals->{default_db});
            }
         }
         else {
            my $converted = $qr->convert_to_select($samp_query);
            if ( $converted
                 && $converted =~ m/^[\(\s]*select/i ) {
               $vals->{for_explain} = "EXPLAIN /*!50100 PARTITIONS*/\n$converted\\G\n";
            }
         }
      }
      else {
         if ( $groupby eq 'tables' ) {
            my ( $db, $tbl ) = $q->split_unquote($item);
            $vals->{tables_report} = $self->tables_report([$db, $tbl]);
         }
      }
   }

   return encode_json($query_report_vals) . "\n";
};

1;
}

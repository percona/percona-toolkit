# This program is copyright 2013 Percona Ireland Ltd.
# Feedback and improvements are welcome.
#
# THIS PROGRAM IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR IMPLIED
# WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED WARRANTIES OF
# MERCHANTIBILITY AND FITNESS FOR A PARTICULAR PURPOSE.
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, version 2; OR the Perl Artistic License.  On UNIX and similar
# systems, you can issue `man perlgpl' or `man perlartistic' to read these
# licenses.
#
# You should have received a copy of the GNU General Public License along with
# this program; if not, write to the Free Software Foundation, Inc., 59 Temple
# Place, Suite 330, Boston, MA  02111-1307  USA.
# ###########################################################################
# JSONReportFormatter package
# ###########################################################################
{
package JSONReportFormatter;
use Lmo;

use List::Util   qw(sum);
use Transformers qw(make_checksum parse_timestamp);

use constant PTDEBUG => $ENV{PTDEBUG} || 0;

my $have_json = eval { require JSON };

our $pretty_json = $ENV{PTTEST_PRETTY_JSON} || 0;
our $sorted_json = $ENV{PTTEST_PRETTY_JSON} || 0;

extends qw(QueryReportFormatter);

has 'QueryRewriter' => (
   is       => 'ro',
   isa      => 'Object',
   required => 1,
);

has 'QueryParser' => (
   is       => 'ro',
   isa      => 'Object',
   required => 1,
);

has 'Quoter' => (
   is       => 'ro',
   isa      => 'Object',
   required => 1,
);

has _json => (
   is       => 'ro',
   init_arg => undef,
   builder  => '_build_json',
);

sub _build_json {
   return unless $have_json;
   return JSON->new->utf8
                   ->pretty($pretty_json)
                   ->canonical($sorted_json);
}

sub encode_json {
   my ($self, $encode) = @_;
   if ( my $json = $self->_json ) {
      return $json->encode($encode);
   }
   else {
      return Transformers::encode_json($encode);
   }
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
   my $ea      = $args{ea};
   my $worst   = $args{worst};
   my $orderby = $args{orderby};
   my $groupby = $args{groupby};

   my $results = $ea->results();
   my @attribs = @{$ea->get_attributes()};
   
   my $q  = $self->Quoter;
   my $qr = $self->QueryRewriter;

   # ########################################################################
   # Global data
   # ########################################################################
   my $global_data = {
      metrics => {},
   };

   # Get global count
   my $global_cnt = $results->{globals}->{$orderby}->{cnt} || 0;
   my $global_unq = scalar keys %{$results->{classes}};

   # Calculate QPS (queries per second) by looking at the min/max timestamp.
   my ($qps, $conc) = (0, 0);
   if ( $global_cnt && $results->{globals}->{ts}
        && ($results->{globals}->{ts}->{max} || '')
            gt ($results->{globals}->{ts}->{min} || '') )
   {
      eval {
         my $min  = parse_timestamp($results->{globals}->{ts}->{min});
         my $max  = parse_timestamp($results->{globals}->{ts}->{max});
         my $diff = unix_timestamp($max) - unix_timestamp($min);
         $qps     = $global_cnt / ($diff || 1);
         $conc    = $results->{globals}->{$orderby}->{sum} / $diff;
      };
   }

   $global_data->{query_count}        = $global_cnt;
   $global_data->{unique_query_count} = $global_unq;
   $global_data->{queries_per_second} = $qps  if $qps;
   $global_data->{concurrency}        = $conc if $conc;

   my %hidden_attrib = (
      arg         => 1,
      fingerprint => 1,
      pos_in_log  => 1,
      ts          => 1,
      bytes       => 1,
   );
   foreach my $attrib ( grep { !$hidden_attrib{$_} } @attribs ) {
      my $type = $ea->type_for($attrib) || 'string';
      next if $type eq 'string';
      next unless exists $results->{globals}->{$attrib};

      my $store   = $results->{globals}->{$attrib};
      my $metrics = $ea->stats()->{globals}->{$attrib};
      my $int     = $attrib =~ m/(?:time|wait)$/ ? 0 : 1;

      if ( $type eq 'num' ) {
         foreach my $m ( qw(sum min max) ) { 
            if ( $int ) {
               $global_data->{metrics}->{$attrib . "_$m"}
                  = sprintf('%d', $store->{$m} || 0);
            }
            else {  # microsecond
               $global_data->{metrics}->{$attrib . "_$m"}
                  = sprintf('%.6f',  $store->{$m} || 0);
            }
         }
         foreach my $m ( qw(pct_95 stddev median) ) {
            if ( $int ) {
               $global_data->{metrics}->{$attrib . "_$m"}
                  = sprintf('%d', $metrics->{$m} || 0);
            }
            else {  # microsecond
               $global_data->{metrics}->{$attrib . "_$m"}
                  = sprintf('%.6f',  $metrics->{$m} || 0);
            }
         }
         if ( $int ) {
            $global_data->{metrics}->{$attrib . "_avg"}
               = sprintf('%d', $store->{sum} / $store->{cnt});
         }
         else {
            $global_data->{metrics}->{$attrib . "_avg"}
               = sprintf('%.6f', $store->{sum} / $store->{cnt});
         }  
      }
      elsif ( $type eq 'bool' ) {
         my $store = $results->{globals}->{$attrib};
         $global_data->{metrics}->{$attrib . "_cnt"}
            = sprintf('%d', $store->{sum});
      }
   }

   # ########################################################################
   # Query class data
   # ########################################################################

   my @queries;

   foreach my $worst_info ( @$worst ) {
      my $item   = $worst_info->[0];
      my $stats  = $ea->results->{classes}->{$item};
      my $sample = $ea->results->{samples}->{$item};

      my $all_log_pos = $ea->{result_classes}->{$item}->{pos_in_log}->{all};
      my $times_seen  = sum values %$all_log_pos;

      # Distill the query.
      my $distill = $groupby eq 'fingerprint' ? $qr->distill($sample->{arg})
                  :                             undef;

      my %class = (
         attribute   => $groupby,
         fingerprint => $item,
         checksum    => make_checksum($item),
         distillate  => $distill,
         query_count => $times_seen,
         example     => {
            query => $sample->{arg},
            ts    => $sample->{ts} ? parse_timestamp($sample->{ts}) : undef,
         },
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
         delete $metrics{pos_in_log};
         delete $metrics{$attrib}->{cnt};

         if ($attrib eq 'ts') {
            my $ts = delete $metrics{ts};
            foreach my $thing ( qw(min max) ) {
               next unless defined $ts && defined $ts->{$thing};
               $ts->{$thing} = parse_timestamp($ts->{$thing});
            }
            $class{ts_min} = $ts->{min};
            $class{ts_max} = $ts->{max};
         }
         else {
            my $type = $ea->type_for($attrib) || 'string';
            if ( $type eq 'string' ) {
               $metrics{$attrib} = { value => $metrics{$attrib}{max} }; 
            }
            elsif ( $type eq 'num' ) {
               # Avoid scientific notation in the metrics by forcing it to use
               # six decimal places.
               foreach my $value ( values %{$metrics{$attrib}} ) {
                  next unless defined $value;
                  if ( $attrib =~ m/_(?:time|wait)$/ ) {
                     $value = sprintf('%.6f', $value);
                  }
                  else {
                     $value = sprintf('%d', $value);
                  }
               }
            }
            elsif ( $type eq 'bool' ) {
               $metrics{$attrib} = {
                  yes => sprintf('%d', $metrics{$attrib}->{sum}),
               };
            }
         }
      }

      # Add "copy-paste" info, i.e. this stuff from the regular report:
      # 
      # Tables
      #    SHOW TABLE STATUS FROM `db2` LIKE 'tuningdetail_21_265507'\G
      #    SHOW CREATE TABLE `db2`.`tuningdetail_21_265507`\G
      #    SHOW TABLE STATUS FROM `db1` LIKE 'gonzo'\G
      #    SHOW CREATE TABLE `db1`.`gonzo`\G
      #     update db2.tuningdetail_21_265507 n
      #           inner join db1.gonzo a using(gonzo) 
      #                 set n.column1 = a.column1, n.word3 = a.word3\G
      # Converted for EXPLAIN
      # EXPLAIN /*!50100 PARTITIONS*/
      #    select  n.column1 = a.column1, n.word3 = a.word3
      #    from db2.tuningdetail_21_265507 n
      #    inner join db1.gonzo a using(gonzo) \G
      #
      # The formatting isn't included, just the useful data, like:
      #
      # $copy_paste = {
      #    tables => {
      #      create => "SHOW CREATE TABLE db.foo",
      #      status => "SHOW TABLE STATUS FROM db LIKE foo",
      #    },
      #    explain => "select ..."
      # }
      #
      # This is called "copy-paste" because users can copy-paste these
      # ready-made lines into MySQL.
      my $copy_paste;
      if ( $groupby eq 'fingerprint' ) {
         # Get SHOW CREATE TABLE and SHOW TABLE STATUS.
         my $default_db = $sample->{db}       ? $sample->{db}
                        : $stats->{db}->{unq} ? keys %{$stats->{db}->{unq}}
                        :                       undef;
         my @table_names = $self->QueryParser->extract_tables(
            query      => $sample->{arg} || '',
            default_db => $default_db,
            Quoter     => $q,
         );
         my @tables;
         foreach my $db_tbl ( @table_names ) {
            my ( $db, $tbl ) = @$db_tbl;
            my $status
               = 'SHOW TABLE STATUS'
               . ($db ? " FROM `$db`" : '')
               . " LIKE '$tbl'\\G";
            my $create
               = "SHOW CREATE TABLE "
               . $q->quote(grep { $_ } @$db_tbl)
               . "\\G";
            push @tables, { status => $status, create => $create };
         }
         if ( @tables ) {
            $copy_paste->{tables} = \@tables;
         }

         # Convert possible non-SELECTs for EXPLAIN.
         if ( $item =~ m/^(?:[\(\s]*select|insert|replace)/ ) {
            if ( $item =~ m/^(?:insert|replace)/ ) {
               # Cannot convert or EXPLAIN INSERT or REPLACE queries.
            }
            else {
               # SELECT queries don't need to converted for EXPLAIN.

               # TODO: return the actual EXPLAIN plan
               # $self->explain_report($query, $vals->{default_db});
            }
         }
         else {
            # Query is not SELECT, INSERT, or REPLACE, so we can convert
            # it for EXPLAIN.
            my $converted = $qr->convert_to_select(
               $sample->{arg} || '',
            );
            if ( $converted && $converted =~ m/^[\(\s]*select/i ) {
               $copy_paste->{explain} = $converted;
            }
         }
      }

      push @queries, {
         class       => \%class,
         attributes  => \%metrics,
         ($copy_paste ? (copy_paste  => $copy_paste) : ()),
      };
   }

   # ########################################################################
   # Done, combine, encode, and return global and query class data
   # ########################################################################
   my $data = {
      global  => $global_data,
      classes => \@queries,
   };
   my $json = $self->encode_json($data);
   $json .= "\n" unless $json =~ /\n\Z/;
   return $json;
};

no Lmo;
1;
}
# ###########################################################################
# End JSONReportFormatter package
# ###########################################################################

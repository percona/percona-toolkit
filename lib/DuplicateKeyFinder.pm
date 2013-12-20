# This program is copyright 2009-2011 Percona Ireland Ltd.
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
# DuplicateKeyFinder package
# ###########################################################################
{
# Package: DuplicateKeyFinder
# DuplicateKeyFinder finds duplicate indexes (keys).
package DuplicateKeyFinder;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

sub new {
   my ( $class, %args ) = @_;
   my $self = {};
   return bless $self, $class;
}

# %args should contain:
#
#  *  keys             (req) A hashref from TableParser::get_keys().
#  *  clustered_key    The clustered key, if any; also from get_keys().
#  *  tbl_info         { db, tbl, engine, ddl } hashref.
#  *  callback         An anonymous subroutine, called for each dupe found.
#  *  ignore_order     Order never matters for any type of index (generally
#                      order matters except for FULLTEXT).
#  *  ignore_structure Compare different index types as if they're the same.
#  *  clustered        Perform duplication checks against the clustered  key.
#
# Returns an arrayref of duplicate key hashrefs.  Each contains
#
#  *  key               The name of the index that's a duplicate.
#  *  cols              The columns in that key (arrayref).
#  *  duplicate_of      The name of the index it duplicates.
#  *  duplicate_of_cols The columns of the index it duplicates.
#  *  reason            A human-readable description of why this is a duplicate.
#  *  dupe_type         Either exact, prefix, fk, or clustered.
#
sub get_duplicate_keys {
   my ( $self, $keys,  %args ) = @_;
   die "I need a keys argument" unless $keys;
   my %keys = %$keys;  # Copy keys because we remove non-duplicates.
   my $primary_key;
   my @unique_keys;
   my @normal_keys;
   my @fulltext_keys;
   my @dupes;

   KEY:
   foreach my $key ( values %keys ) {
      # Save real columns before we potentially re-order them.  These are
      # columns we want to print if the key is a duplicate.
      $key->{real_cols} = [ @{$key->{cols}} ];

      # We use column lengths to compare keys.
      $key->{len_cols}  = length $key->{colnames};

      # The primary key is treated specially.  It is effectively never a
      # duplicate, so it is never removed.  It is compared to all other
      # keys, and in any case of duplication, the primary is always kept
      # and the other key removed.  Usually the primary is the acutal
      # PRIMARY KEY, but for an InnoDB table without a PRIMARY KEY, the
      # effective primary key is the clustered key.
      if ( $key->{name} eq 'PRIMARY'
           || ($args{clustered_key} && $key->{name} eq $args{clustered_key}) ) {
         $primary_key = $key;
         PTDEBUG && _d('primary key:', $key->{name});
         next KEY;
      }

      # Key column order matters for all keys except FULLTEXT, so unless
      # ignore_order is specified we only sort FULLTEXT keys.
      my $is_fulltext = $key->{type} eq 'FULLTEXT' ? 1 : 0;
      if ( $args{ignore_order} || $is_fulltext  ) {
         my $ordered_cols = join(',', sort(split(/,/, $key->{colnames})));
         PTDEBUG && _d('Reordered', $key->{name}, 'cols from',
            $key->{colnames}, 'to', $ordered_cols); 
         $key->{colnames} = $ordered_cols;
      }

      # Unless ignore_structure is specified, only keys of the same
      # structure (btree, fulltext, etc.) are compared to one another.
      # UNIQUE keys are kept separate to make comparisons easier.
      my $push_to = $key->{is_unique} ? \@unique_keys : \@normal_keys;
      if ( !$args{ignore_structure} ) {
         $push_to = \@fulltext_keys if $is_fulltext;
         # TODO:
         # $push_to = \@hash_keys     if $is_hash;
         # $push_to = \@spatial_keys  if $is_spatial;
      }
      push @$push_to, $key; 
   }

   # Redundantly constrained unique keys are treated as normal keys.
   push @normal_keys, $self->unconstrain_keys($primary_key, \@unique_keys);

   # Do not check the primary key against uniques before unconstraining
   # redundantly unique keys.  In cases like
   #    PRIMARY KEY (a, b)
   #    UNIQUE KEY  (a)
   # the unique key will be wrongly removed.  It is needed to keep
   # column a unique.  The process of unconstraining redundantly unique
   # keys marks single column unique keys so that they are never removed
   # (the mark is adding unique_col=>1 to the unique key's hash).
   if ( $primary_key ) {
      PTDEBUG && _d('Comparing PRIMARY KEY to UNIQUE keys');
      push @dupes,
         $self->remove_prefix_duplicates([$primary_key], \@unique_keys, %args);

      PTDEBUG && _d('Comparing PRIMARY KEY to normal keys');
      push @dupes,
         $self->remove_prefix_duplicates([$primary_key], \@normal_keys, %args);
   }

   PTDEBUG && _d('Comparing UNIQUE keys to normal keys');
   push @dupes,
      $self->remove_prefix_duplicates(\@unique_keys, \@normal_keys, %args);

   PTDEBUG && _d('Comparing normal keys');
   push @dupes,
      $self->remove_prefix_duplicates(\@normal_keys, \@normal_keys, %args);

   # If --allstruct, then these special struct keys (FULLTEXT, HASH, etc.)
   # will have already been put in and handled by @normal_keys.
   PTDEBUG && _d('Comparing FULLTEXT keys');
   push @dupes,
      $self->remove_prefix_duplicates(\@fulltext_keys, \@fulltext_keys, %args, exact_duplicates => 1);

   # Remove clustered duplicates.
   my $clustered_key = $args{clustered_key} ? $keys{$args{clustered_key}}
                     : undef;
   PTDEBUG && _d('clustered key:',
      $clustered_key ? ($clustered_key->{name}, $clustered_key->{colnames})
                     : 'none');
   if ( $clustered_key
        && $args{clustered}
        && $args{tbl_info}->{engine}
        && $args{tbl_info}->{engine} =~ m/InnoDB/i )
   {
      PTDEBUG && _d('Removing UNIQUE dupes of clustered key');
      push @dupes,
         $self->remove_clustered_duplicates($clustered_key, \@unique_keys, %args);

      PTDEBUG && _d('Removing ordinary dupes of clustered key');
      push @dupes,
         $self->remove_clustered_duplicates($clustered_key, \@normal_keys, %args);
   }

   return \@dupes;
}

sub get_duplicate_fks {
   my ( $self, $fks, %args ) = @_;
   die "I need a fks argument" unless $fks;
   my @fks = values %$fks;
   my @dupes;

   foreach my $i ( 0..$#fks - 1 ) {
      next unless $fks[$i];
      foreach my $j ( $i+1..$#fks ) {
         next unless $fks[$j];

         # A foreign key is a duplicate no matter what order the
         # columns are in, so re-order them alphabetically so they
         # can be compared.
         my $i_cols  = join(',', sort @{$fks[$i]->{cols}} );
         my $j_cols  = join(',', sort @{$fks[$j]->{cols}} );
         my $i_pcols = join(',', sort @{$fks[$i]->{parent_cols}} );
         my $j_pcols = join(',', sort @{$fks[$j]->{parent_cols}} );

         if ( $fks[$i]->{parent_tblname} eq $fks[$j]->{parent_tblname}
              && $i_cols  eq $j_cols
              && $i_pcols eq $j_pcols ) {
            my $dupe = {
               key               => $fks[$j]->{name},
               cols              => [ @{$fks[$j]->{cols}} ],
               ddl               => $fks[$j]->{ddl},
               duplicate_of      => $fks[$i]->{name},
               duplicate_of_cols => [ @{$fks[$i]->{cols}} ],
               duplicate_of_ddl  => $fks[$i]->{ddl},
               reason            =>
                    "FOREIGN KEY $fks[$j]->{name} ($fks[$j]->{colnames}) "
                  . "REFERENCES $fks[$j]->{parent_tblname} "
                  . "($fks[$j]->{parent_colnames}) "
                  . 'is a duplicate of '
                  . "FOREIGN KEY $fks[$i]->{name} ($fks[$i]->{colnames}) "
                  . "REFERENCES $fks[$i]->{parent_tblname} "
                  ."($fks[$i]->{parent_colnames})",
               dupe_type         => 'fk',
            };
            push @dupes, $dupe;
            delete $fks[$j];
            $args{callback}->($dupe, %args) if $args{callback};
         }
      }
   }
   return \@dupes;
}

# Removes and returns prefix duplicate keys from right_keys.
# Both left_keys and right_keys are arrayrefs.
#
# Prefix duplicates are the typical type of duplicate like:
#    KEY x (a)
#    KEY y (a, b)
# Key x is a prefix duplicate of key y.  This also covers exact
# duplicates like:
#    KEY y (a, b)
#    KEY z (a, b)
# Key y and z are exact duplicates.
#
# Usually two separate lists of keys are compared: the left and right
# keys.  When a duplicate is found, the Left key is Left alone and the
# Right key is Removed. This is done because some keys are more important
# than others.  For example, the PRIMARY KEY is always a left key because
# it is never removed.  When comparing UNIQUE keys to normal (non-unique)
# keys, the UNIQUE keys are Left (alone) and any duplicating normal
# keys are Removed.
#
# A list of keys can be compared to itself in which case left and right
# keys reference the same list but this sub doesn't know that so it just
# removes dupes from the left as usual.
#
# Optional args are:
#    * exact_duplicates  Keys are dupes only if they're exact duplicates
#    * callback          Sub called for each dupe found
# 
# For a full technical explanation of how/why this sub works, read:
# http://code.google.com/p/maatkit/wiki/DeterminingDuplicateKeys
sub remove_prefix_duplicates {
   my ( $self, $left_keys, $right_keys, %args ) = @_;
   my @dupes;
   my $right_offset;
   my $last_left_key;
   my $last_right_key = scalar(@$right_keys) - 1;

   # We use "scalar(@$arrayref) - 1" because the $# syntax is not
   # reliable with arrayrefs across Perl versions.  And we use index
   # into the arrays because we delete elements.

   if ( $right_keys != $left_keys ) {
      # Right and left keys are different lists.

      @$left_keys = sort { lc($a->{colnames}) cmp lc($b->{colnames}) }
                    grep { defined $_; }
                    @$left_keys;
      @$right_keys = sort { lc($a->{colnames}) cmp lc($b->{colnames}) }
                     grep { defined $_; }
                    @$right_keys;

      # Last left key is its very last key.
      $last_left_key = scalar(@$left_keys) - 1;

      # No need to offset where we begin looping through the right keys.
      $right_offset = 0;
   }
   else {
      # Right and left keys are the same list.

      @$left_keys = reverse sort { lc($a->{colnames}) cmp lc($b->{colnames}) }
                    grep { defined $_; }
                    @$left_keys;
      
      # Last left key is its second-to-last key.
      # The very last left key will be used as a right key.
      $last_left_key = scalar(@$left_keys) - 2;

      # Since we're looping through the same list in two different
      # positions, we must offset where we begin in the right keys
      # so that we stay ahead of where we are in the left keys.
      $right_offset = 1;
   }

   LEFT_KEY:
   foreach my $left_index ( 0..$last_left_key ) {
      next LEFT_KEY unless defined $left_keys->[$left_index];

      RIGHT_KEY:
      foreach my $right_index ( $left_index+$right_offset..$last_right_key ) {
         next RIGHT_KEY unless defined $right_keys->[$right_index];

         my $left_name      = $left_keys->[$left_index]->{name};
         my $left_cols      = $left_keys->[$left_index]->{colnames};
         my $left_len_cols  = $left_keys->[$left_index]->{len_cols};
         my $right_name     = $right_keys->[$right_index]->{name};
         my $right_cols     = $right_keys->[$right_index]->{colnames};
         my $right_len_cols = $right_keys->[$right_index]->{len_cols};

         PTDEBUG && _d('Comparing left', $left_name, '(',$left_cols,')',
            'to right', $right_name, '(',$right_cols,')');

         # Compare the whole right key to the left key, not just
         # the their common minimum length prefix. This is correct.
         # Read http://code.google.com/p/maatkit/wiki/DeterminingDuplicateKeys.
         if (    substr($left_cols,  0, $right_len_cols)
              eq substr($right_cols, 0, $right_len_cols) ) {

            # UNIQUE and FULLTEXT indexes are only duplicates if they
            # are exact duplicates.
            if ( $args{exact_duplicates} && ($right_len_cols<$left_len_cols) ) {
               PTDEBUG && _d($right_name, 'not exact duplicate of', $left_name);
               next RIGHT_KEY;
            }

            # Do not remove the unique key that is constraining a single
            # column to uniqueness. This prevents UNIQUE KEY (a) from being
            # removed by PRIMARY KEY (a, b).
            if ( exists $right_keys->[$right_index]->{unique_col} ) {
               PTDEBUG && _d('Cannot remove', $right_name,
                  'because is constrains col',
                  $right_keys->[$right_index]->{cols}->[0]);
               next RIGHT_KEY;
            }

            PTDEBUG && _d('Remove', $right_name);
            my $reason;
            if ( my $type = $right_keys->[$right_index]->{unconstrained} ) {
               $reason .= "Uniqueness of $right_name ignored because "
                  . $right_keys->[$right_index]->{constraining_key}->{name}
                  . " is a $type constraint\n"; 
            }
            my $exact_dupe = $right_len_cols < $left_len_cols ? 0 : 1;
            $reason .= $right_name
                     . ($exact_dupe ? ' is a duplicate of '
                                    : ' is a left-prefix of ')
                     . $left_name;
            my $dupe = {
               key               => $right_name,
               cols              => $right_keys->[$right_index]->{real_cols},
               ddl               => $right_keys->[$right_index]->{ddl},
               duplicate_of      => $left_name,
               duplicate_of_cols => $left_keys->[$left_index]->{real_cols},
               duplicate_of_ddl  => $left_keys->[$left_index]->{ddl},
               reason            => $reason,
               dupe_type         => $exact_dupe ? 'exact' : 'prefix',
            };
            push @dupes, $dupe;
            delete $right_keys->[$right_index];

            $args{callback}->($dupe, %args) if $args{callback};
         }
         else {
            PTDEBUG && _d($right_name, 'not left-prefix of', $left_name);
            next RIGHT_KEY;
         }
      } # RIGHT_KEY
   } # LEFT_KEY
   PTDEBUG && _d('No more keys');

   # Cleanup the lists: remove removed keys.
   @$left_keys  = grep { defined $_; } @$left_keys;
   @$right_keys = grep { defined $_; } @$right_keys;

   return @dupes;
}

# Removes and returns clustered duplicate keys from keys.
# ck (clustered key) is hashref and keys is an arrayref.
#
# For engines with a clustered index, if a key ends with a prefix
# of the primary key, it's a duplicate. Example:
#    PRIMARY KEY (a)
#    KEY foo (b, a)
# Key foo is redundant to PRIMARY.
#
# Optional args are:
#    * callback          Sub called for each dupe found
#
sub remove_clustered_duplicates {
   my ( $self, $ck, $keys, %args ) = @_;
   die "I need a ck argument"   unless $ck;
   die "I need a keys argument" unless $keys;
   my $ck_cols = $ck->{colnames};

   my @dupes;
   KEY:
   for my $i ( 0 .. @$keys - 1 ) {
      my $key = $keys->[$i]->{colnames};
      if ( $key =~ m/$ck_cols$/ ) {
         PTDEBUG && _d("clustered key dupe:", $keys->[$i]->{name},
            $keys->[$i]->{colnames});
         my $dupe = {
            key               => $keys->[$i]->{name},
            cols              => $keys->[$i]->{real_cols},
            ddl               => $keys->[$i]->{ddl},
            duplicate_of      => $ck->{name},
            duplicate_of_cols => $ck->{real_cols},
            duplicate_of_ddl  => $ck->{ddl},
            reason            => "Key $keys->[$i]->{name} ends with a "
                               . "prefix of the clustered index",
            dupe_type         => 'clustered',
            short_key         => $self->shorten_clustered_duplicate(
                                    $ck_cols,
                                    join(',', map { "`$_`" }
                                       @{$keys->[$i]->{real_cols}})
                                 ),
         };
         push @dupes, $dupe;
         delete $keys->[$i];
         $args{callback}->($dupe, %args) if $args{callback};
      }
   }
   PTDEBUG && _d('No more keys');

   # Cleanup the lists: remove removed keys.
   @$keys = grep { defined $_; } @$keys;

   return @dupes;
}

sub shorten_clustered_duplicate {
   my ( $self, $ck_cols, $dupe_key_cols ) = @_;
   return $ck_cols if $ck_cols eq $dupe_key_cols;
   $dupe_key_cols =~ s/$ck_cols$//;
   $dupe_key_cols =~ s/,+$//;
   return $dupe_key_cols;
}

# Given a primary key (can be undef) and an arrayref of unique keys,
# removes and returns redundantly contrained unique keys from uniquie_keys.
sub unconstrain_keys {
   my ( $self, $primary_key, $unique_keys ) = @_;
   die "I need a unique_keys argument" unless $unique_keys;
   my %unique_cols;
   my @unique_sets;
   my %unconstrain;
   my @unconstrained_keys;

   PTDEBUG && _d('Unconstraining redundantly unique keys');

   # First determine which unique keys define unique columns
   # and which define unique sets.
   UNIQUE_KEY:
   foreach my $unique_key ( $primary_key, @$unique_keys ) {
      next unless $unique_key; # primary key may be undefined
      my $cols = $unique_key->{cols};
      if ( @$cols == 1 ) {
         if ( !exists $unique_cols{$cols->[0]} ) {
            PTDEBUG && _d($unique_key->{name}, 'defines unique column:',
               $cols->[0]);
            $unique_cols{$cols->[0]}  = $unique_key;
            $unique_key->{unique_col} = 1;
         }
         else {
            # https://bugs.launchpad.net/percona-toolkit/+bug/1217013
            # If two unique indexes are not exact, then they must be enforcing
            # different uniqueness constraints.  Else they're exact dupes
            # so one can be treated as a non-unique and removed later
            # when comparing unique to non-unique.
            PTDEBUG && _d($unique_key->{name},
               'redundantly constrains unique column:', $cols->[0]);
            $unique_key->{exact_dupe} = 1;
            $unique_key->{constraining_key} = $unique_cols{$cols->[0]};
         }
      }
      else {
         local $LIST_SEPARATOR = '-';
         PTDEBUG && _d($unique_key->{name}, 'defines unique set:', @$cols);
         push @unique_sets, { cols => $cols, key => $unique_key };
      }
   }

   # Second, find which unique sets can be unconstraind (i.e. those
   # which have which have at least one unique column).
   UNIQUE_SET:
   foreach my $unique_set ( @unique_sets ) {
      my $n_unique_cols = 0;
      COL:
      foreach my $col ( @{$unique_set->{cols}} ) {
         if ( exists $unique_cols{$col} ) {
            PTDEBUG && _d('Unique set', $unique_set->{key}->{name},
               'has unique col', $col);
            last COL if ++$n_unique_cols > 1;
            $unique_set->{constraining_key} = $unique_cols{$col};
         }
      }
      if ( $n_unique_cols && $unique_set->{key}->{name} ne 'PRIMARY' ) {
         # Unique set is redundantly constrained.
         PTDEBUG && _d('Will unconstrain unique set',
            $unique_set->{key}->{name},
            'because it is redundantly constrained by key',
            $unique_set->{constraining_key}->{name},
            '(',$unique_set->{constraining_key}->{colnames},')');
         $unconstrain{$unique_set->{key}->{name}}
            = $unique_set->{constraining_key};
      }
   }

   # And finally, unconstrain the redundantly unique sets found above by
   # removing them from the list of unique keys and adding them to the
   # list of normal keys.
   for my $i ( 0..(scalar @$unique_keys-1) ) {
      if ( exists $unconstrain{$unique_keys->[$i]->{name}} ) {
         PTDEBUG && _d('Unconstraining weak', $unique_keys->[$i]->{name});
         $unique_keys->[$i]->{unconstrained} = 'stronger';
         $unique_keys->[$i]->{constraining_key}
            = $unconstrain{$unique_keys->[$i]->{name}};
         push @unconstrained_keys, $unique_keys->[$i];
         delete $unique_keys->[$i];
      }
      elsif ( $unique_keys->[$i]->{exact_dupe} ) {
         # https://bugs.launchpad.net/percona-toolkit/+bug/1217013
         PTDEBUG && _d('Unconstraining dupe', $unique_keys->[$i]->{name});
         $unique_keys->[$i]->{unconstrained} = 'duplicate';
         push @unconstrained_keys, $unique_keys->[$i];
         delete $unique_keys->[$i];
      }
   }

   PTDEBUG && _d('No more keys');
   return @unconstrained_keys;
}

sub _d {
   my ($package, undef, $line) = caller 0;
   @_ = map { (my $temp = $_) =~ s/\n/\n# /g; $temp; }
        map { defined $_ ? $_ : 'undef' }
        @_;
   print STDERR "# $package:$line $PID ", join(' ', @_), "\n";
}

1;
}
# ###########################################################################
# End DuplicateKeyFinder package
# ###########################################################################

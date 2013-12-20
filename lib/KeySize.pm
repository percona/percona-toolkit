# This program is copyright 2008-2011 Percona Ireland Ltd.
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
# KeySize package
# ###########################################################################
{
# Package: KeySize
# KeySize calculates the size of MySQL indexes (keys).
package KeySize;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

sub new {
   my ( $class, %args ) = @_;
   my $self = { %args };
   return bless $self, $class;
}

# Returns the key's size and the key that MySQL actually chose.
# Required args:
#    name       => name of key
#    cols       => arrayref of key's cols
#    tbl_name   => quoted, db-qualified table name like `db`.`tbl`
#    tbl_struct => hashref returned by TableParser::parse for tbl
#    dbh        => dbh
# If the key exists in the tbl (it should), then we can FORCE INDEX.
# This is what we want to do because it's more reliable.  But, if the
# key does not exist in the tbl (which happens with foreign keys),
# then we let MySQL choose the index.  If there's an error, nothing
# is returned and you can get the last error, query and EXPLAIN with
# error(), query() and explain().
sub get_key_size {
   my ( $self, %args ) = @_;
   foreach my $arg ( qw(name cols tbl_name tbl_struct dbh) ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my $name = $args{name};
   my @cols = @{$args{cols}};
   my $dbh  = $args{dbh};

   $self->{explain} = '';
   $self->{query}   = '';
   $self->{error}   = '';

   if ( @cols == 0 ) {
      $self->{error} = "No columns for key $name";
      return;
   }

   my $key_exists = $self->_key_exists(%args);
   PTDEBUG && _d('Key', $name, 'exists in', $args{tbl_name}, ':',
      $key_exists ? 'yes': 'no');

   # Construct a SQL statement with WHERE conditions on all key
   # cols that will get EXPLAIN to tell us 1) the full length of
   # the key and 2) the total number of rows in the table.
   # For 1), all key cols must be used because key_len in EXPLAIN only
   # only covers the portion of the key needed to satisfy the query.
   # For 2), we have to break normal index usage which normally
   # allows MySQL to access only the limited number of rows needed
   # to satisify the query because we want to know total table rows.
   my $sql = 'EXPLAIN SELECT ' . join(', ', @cols)
           . ' FROM ' . $args{tbl_name}
           . ($key_exists ? " FORCE INDEX (`$name`)" : '')
           . ' WHERE ';
   my @where_cols;
   foreach my $col ( @cols ) {
      push @where_cols, "$col=1";
   }
   # For single column indexes we have to trick MySQL into scanning
   # the whole index by giving it two irreducible condtions. Otherwise,
   # EXPLAIN rows will report only the rows that satisfy the query
   # using the key, but this is not what we want. We want total table rows.
   # In other words, we need an EXPLAIN type index, not ref or range.
   if ( scalar(@cols) == 1 && !$args{only_eq} ) {
      push @where_cols, "$cols[0]<>1";
   }
   $sql .= join(' OR ', @where_cols);
   $self->{query} = $sql;
   PTDEBUG && _d('sql:', $sql);

   my $explain;
   my $sth = $dbh->prepare($sql);
   eval { $sth->execute(); };
   if ( $EVAL_ERROR ) {
      chomp $EVAL_ERROR;
      $self->{error} = "Cannot get size of $name key: $EVAL_ERROR";
      return;
   }
   $explain = $sth->fetchrow_hashref();

   $self->{explain} = $explain;
   my $key_len      = $explain->{key_len};
   my $rows         = $explain->{rows};
   my $chosen_key   = $explain->{key};  # May differ from $name
   PTDEBUG && _d('MySQL chose key:', $chosen_key, 'len:', $key_len,
      'rows:', $rows);

   # https://bugs.launchpad.net/percona-toolkit/+bug/1201443
   if ( $chosen_key && $key_len eq '0' ) {
      if ( $args{recurse} ) {
         $self->{error} = "key_len = 0 in EXPLAIN:\n"
                        . _explain_to_text($explain);
         return;
      }
      else {
         return $self->get_key_size(
            %args,
            only_eq => 1,
            recurse => 1,
         );
      }
   }

   my $key_size = 0;
   if ( $key_len && $rows ) {
      if ( $chosen_key =~ m/,/ && $key_len =~ m/,/ ) {
         $self->{error} = "MySQL chose multiple keys: $chosen_key";
         return;
      }
      $key_size = $key_len * $rows;
   }
   else {
      $self->{error} = "key_len or rows NULL in EXPLAIN:\n"
                     . _explain_to_text($explain);
      return;
   }

   return $key_size, $chosen_key;
}

# Returns the last explained query.
sub query {
   my ( $self ) = @_;
   return $self->{query};
}

# Returns the last explain plan.
sub explain {
   my ( $self ) = @_;
   return _explain_to_text($self->{explain});
}

# Returns the last error.
sub error {
   my ( $self ) = @_;
   return $self->{error};
}

sub _key_exists {
   my ( $self, %args ) = @_;
   return exists $args{tbl_struct}->{keys}->{ lc $args{name} } ? 1 : 0;
}

sub _explain_to_text {
   my ( $explain ) = @_;
   return join("\n",
      map { "$_: ".($explain->{$_} ? $explain->{$_} : 'NULL') }
      sort keys %$explain
   );
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
# End KeySize package
# ###########################################################################

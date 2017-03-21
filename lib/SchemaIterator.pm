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
# SchemaIterator package
# ###########################################################################
{
# Package: SchemaIterator
# SchemaIterator iterates schema objects.
package SchemaIterator;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

my $open_comment = qr{/\*!\d{5} };
my $tbl_name     = qr{
   CREATE\s+
   (?:TEMPORARY\s+)?
   TABLE\s+
   (?:IF NOT EXISTS\s+)?
   ([^\(]+)
}x;


# Sub: new
#   Create a new SchemaIterator object with either a dbh or a file_itr.
#
# Parameters:
#   %args - Arguments
#
# Required Arguments:
#   dbh          - dbh to iterate.  Mutually exclusive with file_itr.
#   file_itr     - <FileIterator::get_file_itr()> iterator for dump file.
#                  Mutually exclusive with dbh.
#   OptionParser - <OptionParser> object.  All filters are gotten from this
#                  obj: --databases, --tables, etc.
#   Quoter       - <Quoter> object.
#   TableParser  - <TableParser> object get tbl_struct.
#
# Optional Arguments:
#   Schema          - <Schema> object to initialize while iterating.
#   resume          - Skip tables so first call to <next()> returns
#                     this "db.table".
#
# Returns:
#   SchemaIterator object
sub new {
   my ( $class, %args ) = @_;
   my @required_args = qw(OptionParser TableParser Quoter);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }

   # Either a dbh or a file_itr is required, but not both.
   my ($file_itr, $dbh) = @args{qw(file_itr dbh)};
   die "I need either a dbh or file_itr argument"
      if (!$dbh && !$file_itr) || ($dbh && $file_itr);

   my %resume;
   if ( my $table = $args{resume} ) {
      PTDEBUG && _d('Will resume from or after', $table);
      my ($db, $tbl) = $args{Quoter}->split_unquote($table);
      die "Resume table must be database-qualified: $table"
         unless $db && $tbl;
      $resume{db}  = $db;
      $resume{tbl} = $tbl;
   }

   my $self = {
      %args,
      resume  => \%resume,
      filters => _make_filters(%args),
   };

   return bless $self, $class;
}

# Sub: _make_filters
#   Create schema object filters from <OptionParser> options.  The OptionParser
#   object passed to <new()> is checked for filter options like --database,
#   --tables, --ignore-tables, etc.  For all such options, a hash is built
#   keyed off the same option name.  So $filter{tables} represents --tables,
#   etc.  Regex filters are pre-compiled.  It is very important to avoid
#   auto-vivifying certain key-values; see below.  The filter hash is used
#   in sub like <database_is_allowed()>.
#
#   This sub is called from <new()>.  That's the only place and time it
#   needs to be called because options shouldn't change between runs.
#
# Parameters:
#   %args - Arguments
#
# Required Arguments:
#   OptionParser - <OptionParser> object.  All filters are gotten from this
#                  obj: --databases, --tables, etc.
#   Quoter       - <Quoter> object.
#
# Returns:
#   Hashref of filters keyed on corresponding option names.
sub _make_filters {
   my ( %args ) = @_;
   my @required_args = qw(OptionParser Quoter);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($o, $q) = @args{@required_args};

   my %filters;

   # Do not auto-vivify things like $filters{database} else a check like
   # if ( !$filters{databases}->{foo} ) will be TRUE when it should be FALSE
   # if no --databases where given.  When in doubt: SchemaIterator.t and
   # check test coverage.  These filters must be accurate or else we may
   # access something the user doesn't want us to.

   my @simple_filters = qw(
      databases         tables         engines
      ignore-databases  ignore-tables  ignore-engines);
   FILTER:
   foreach my $filter ( @simple_filters ) {
      if ( $o->has($filter) ) {
         my $objs = $o->get($filter);
         next FILTER unless $objs && scalar keys %$objs;
         my $is_table = $filter =~ m/table/ ? 1 : 0;
         foreach my $obj ( keys %$objs ) {
            die "Undefined value for --$filter" unless $obj;
            $obj = lc $obj;
            if ( $is_table ) {
               my ($db, $tbl) = $q->split_unquote($obj);
               # Database-qualified tables require special handling.
               # See table_is_allowed().
               $db ||= '*';
               PTDEBUG && _d('Filter', $filter, 'value:', $db, $tbl);
               $filters{$filter}->{$db}->{$tbl} = 1;
            }
            else { # database
               PTDEBUG && _d('Filter', $filter, 'value:', $obj);
               $filters{$filter}->{$obj} = 1;
            }
         }
      }
   }

   my @regex_filters = qw(
      databases-regex         tables-regex
      ignore-databases-regex  ignore-tables-regex);
   REGEX_FILTER:
   foreach my $filter ( @regex_filters ) {
      if ( $o->has($filter) ) {
         my $pat = $o->get($filter);
         next REGEX_FILTER unless $pat;
         $filters{$filter} = qr/$pat/;
         PTDEBUG && _d('Filter', $filter, 'value:', $filters{$filter});
      }
   }

   PTDEBUG && _d('Schema object filters:', Dumper(\%filters));
   return \%filters;
}

# Sub: next
#   Return the next schema object or undef when no more schema objects.
#   Only filtered schema objects are returned.  If iterating dump files
#   (i.e. the obj was created with a file_itr arg), then the returned
#   schema object will always have a ddl (see below).  But if iterating
#   a dbh, then you must create the obj with a TableParser obj to get a ddl.
#   If this object was created with a TableParser, then the ddl, if present,
#   is parsed, too.
#
# Returns:
#   Hashref of schema object with at least a db and tbl keys, like
#   (start code)
#   {
#      db         => 'test',
#      tbl        => 'a',
#      ddl        => 'CREATE TABLE `a` ( ...',  # if keep_ddl
#      tbl_struct => <TableParser::parse()> hashref of parsed ddl,
#   }
#   (end code)
#   The ddl is suitable for <TableParser::parse()>.
sub next {
   my ( $self ) = @_;

   if ( !$self->{initialized} ) {
      $self->{initialized} = 1;
      if ( $self->{resume}->{tbl} ) {
         if ( !$self->table_is_allowed(@{$self->{resume}}{qw(db tbl)}) ) {
            PTDEBUG && _d('Will resume after',
               join('.', @{$self->{resume}}{qw(db tbl)}));
            $self->{resume}->{after}->{tbl} = 1;
         }
         if ( !$self->database_is_allowed($self->{resume}->{db}) ) {
            PTDEBUG && _d('Will resume after', $self->{resume}->{db});
            $self->{resume}->{after}->{db}  = 1;
         }
      }
   }

   my $schema_obj;
   if ( $self->{file_itr} ) {
      $schema_obj= $self->_iterate_files();
   }
   else { # dbh
      $schema_obj= $self->_iterate_dbh();
   }

   if ( $schema_obj ) {
      if ( my $schema = $self->{Schema} ) {
         $schema->add_schema_object($schema_obj);
      }
      PTDEBUG && _d('Next schema object:',
         $schema_obj->{db}, $schema_obj->{tbl});
   }

   return $schema_obj;
}

sub _iterate_files {
   my ( $self ) = @_;

   if ( !$self->{fh} ) {
      my ($fh, $file) = $self->{file_itr}->();
      if ( !$fh ) {
         PTDEBUG && _d('No more files to iterate');
         return;
      }
      $self->{fh}   = $fh;
      $self->{file} = $file;
   }
   my $fh = $self->{fh};
   PTDEBUG && _d('Getting next schema object from', $self->{file});

   local $INPUT_RECORD_SEPARATOR = '';
   CHUNK:
   while (defined(my $chunk = <$fh>)) {
      if ($chunk =~ m/Database: (\S+)/) {
         # If the file is a dump of one db, then the only indication of that
         # db is in a comment at the start of the file like,
         #   -- Host: localhost    Database: sakila
         # If the dump is of multiple dbs, then there are both these same
         # comments and USE statements.  We look for the comment which is
         # unique to both single and multi-db dumps.
         my $db = $1; # XXX
         $db =~ s/^`//;  # strip leading `
         $db =~ s/`$//;  # and trailing `
         if ( $self->database_is_allowed($db)
              && $self->_resume_from_database($db) ) {
            $self->{db} = $db;
         }
      }
      elsif ($self->{db} && $chunk =~ m/CREATE TABLE/) {
         if ($chunk =~ m/DROP VIEW IF EXISTS/) {
            # Tables that are actually views have this DROP statment in the
            # chunk just before the CREATE TABLE.  We don't want views.
            PTDEBUG && _d('Table is a VIEW, skipping');
            next CHUNK;
         }

         # The open comment is usually present for a view table, which we
         # probably already detected and skipped above, but this is left her
         # just in case mysqldump wraps other CREATE TABLE statements in a
         # a version comment that I don't know about yet.
         my ($tbl) = $chunk =~ m/$tbl_name/;
         $tbl      =~ s/^\s*`//;
         $tbl      =~ s/`\s*$//;
         if ( $self->_resume_from_table($tbl)
              && $self->table_is_allowed($self->{db}, $tbl) ) {
            my ($ddl) = $chunk =~ m/^(?:$open_comment)?(CREATE TABLE.+?;)$/ms;
            if ( !$ddl ) {
               warn "Failed to parse CREATE TABLE from\n" . $chunk;
               next CHUNK;
            }
            $ddl =~ s/ \*\/;\Z/;/;  # remove end of version comment
            my $tbl_struct = $self->{TableParser}->parse($ddl);
            if ( $self->engine_is_allowed($tbl_struct->{engine}) ) {
               return {
                  db         => $self->{db},
                  tbl        => $tbl,
                  name       => $self->{Quoter}->quote($self->{db}, $tbl),
                  ddl        => $ddl,
                  tbl_struct => $tbl_struct,
               };
            }
         }
      }
   }  # CHUNK

   PTDEBUG && _d('No more schema objects in', $self->{file});
   close $self->{fh};
   $self->{fh} = undef;

   # Recurse to get next file and begin iterating it.  If there's no next
   # file, then the call will return undef and we'll return undef, too
   return $self->_iterate_files();
}

sub _iterate_dbh {
   my ( $self ) = @_;
   my $q   = $self->{Quoter};
   my $tp  = $self->{TableParser};
   my $dbh = $self->{dbh};
   PTDEBUG && _d('Getting next schema object from dbh', $dbh);

   if ( !defined $self->{dbs} ) {
      # This happens once, the first time we're called.
      my $sql = 'SHOW DATABASES';
      PTDEBUG && _d($sql);
      my @dbs = grep {
                  $self->_resume_from_database($_)
                  &&
                  $self->database_is_allowed($_)
                } @{$dbh->selectcol_arrayref($sql)};
      PTDEBUG && _d('Found', scalar @dbs, 'databases');
      $self->{dbs} = \@dbs;
   }

   DATABASE:
   while ( $self->{db} || defined(my $db = shift @{$self->{dbs}}) ) {
      if ( !$self->{db} ) {
         PTDEBUG && _d('Next database:', $db);
         $self->{db} = $db;
      }

      if ( !$self->{tbls} ) {
         my $sql = 'SHOW /*!50002 FULL*/ TABLES FROM ' . $q->quote($self->{db});
         PTDEBUG && _d($sql);
         my @tbls = map {
            $_->[0];  # (tbl, type)
         }
         grep {
            my ($tbl, $type) = @$_;
            (!$type || ($type ne 'VIEW'))
            && $self->_resume_from_table($tbl)
            && $self->table_is_allowed($self->{db}, $tbl);
         }

         eval { @{$dbh->selectall_arrayref($sql)}; };
         if ($EVAL_ERROR) {
             warn "Skipping $self->{db}...";
             $self->{db} = undef;
             next;
         }

         PTDEBUG && _d('Found', scalar @tbls, 'tables in database',$self->{db});
         $self->{tbls} = \@tbls;
      }

      TABLE:
      while ( my $tbl = shift @{$self->{tbls}} ) {
         my $ddl = eval { $tp->get_create_table($dbh, $self->{db}, $tbl) };
         if ( my $e = $EVAL_ERROR ) {
            my $table_name = "$self->{db}.$tbl";
            # SHOW CREATE TABLE failed. This is a bit puzzling;
            # maybe the table got dropped, or crashed. Not much we can
            # do about it; If the table is missing, just PTDEBUG it, but
            # otherwise, warn with the error.
            if ( $e =~ /\QTable '$table_name' doesn't exist/ ) {
               PTDEBUG && _d("$table_name no longer exists");
            }
            else {
               warn "Skipping $table_name because SHOW CREATE TABLE failed: $e";
            }
            next TABLE;
         }

         my $tbl_struct = $tp->parse($ddl);
         if ( $self->engine_is_allowed($tbl_struct->{engine}) ) {
            return {
               db         => $self->{db},
               tbl        => $tbl,
               name       => $q->quote($self->{db}, $tbl),
               ddl        => $ddl,
               tbl_struct => $tbl_struct,
            };
         }
      }

      PTDEBUG && _d('No more tables in database', $self->{db});
      $self->{db}   = undef;
      $self->{tbls} = undef;
   } # DATABASE

   PTDEBUG && _d('No more databases');
   return;
}

sub database_is_allowed {
   my ( $self, $db ) = @_;
   die "I need a db argument" unless $db;

   $db = lc $db;

   my $filter = $self->{filters};

   if ( $db =~ m/^(information_schema|performance_schema|lost\+found|percona_schema)$/ ) {
      PTDEBUG && _d('Database', $db, 'is a system database, ignoring');
      return 0;
   }

   if ( $self->{filters}->{'ignore-databases'}->{$db} ) {
      PTDEBUG && _d('Database', $db, 'is in --ignore-databases list');
      return 0;
   }

   if ( $filter->{'ignore-databases-regex'}
        && $db =~ $filter->{'ignore-databases-regex'} ) {
      PTDEBUG && _d('Database', $db, 'matches --ignore-databases-regex');
      return 0;
   }

   if ( $filter->{'databases'}
        && !$filter->{'databases'}->{$db} ) {
      PTDEBUG && _d('Database', $db, 'is not in --databases list, ignoring');
      return 0;
   }

   if ( $filter->{'databases-regex'}
        && $db !~ $filter->{'databases-regex'} ) {
      PTDEBUG && _d('Database', $db, 'does not match --databases-regex, ignoring');
      return 0;
   }

   return 1;
}

sub table_is_allowed {
   my ( $self, $db, $tbl ) = @_;
   die "I need a db argument"  unless $db;
   die "I need a tbl argument" unless $tbl;

   $db  = lc $db;
   $tbl = lc $tbl;

   my $filter = $self->{filters};

   # Always auto-skip these pseudo tables.
   return 0 if $db eq 'mysql' && $tbl =~ m/^(?:
       general_log
      |gtid_execution
      |innodb_index_stats
      |innodb_table_stats
      |inventory
      |plugin
      |proc
      |slave_master_info
      |slave_relay_log_info
      |slave_worker_info
      |slow_log    
   )$/x;

   return 0 if $db eq 'sys' && $tbl =~ m/^(?:
       sys_config
   )$/x;

   if ( $filter->{'ignore-tables'}->{'*'}->{$tbl} 
         || $filter->{'ignore-tables'}->{$db}->{$tbl}) {
      PTDEBUG && _d('Table', $tbl, 'is in --ignore-tables list');
      return 0;
   }

   if ( $filter->{'ignore-tables-regex'}
        && $tbl =~ $filter->{'ignore-tables-regex'} ) {
      PTDEBUG && _d('Table', $tbl, 'matches --ignore-tables-regex');
      return 0;
   }

   if ( $filter->{'tables'}
        && (!$filter->{'tables'}->{'*'}->{$tbl} && !$filter->{'tables'}->{$db}->{$tbl}) ) { 
      PTDEBUG && _d('Table', $tbl, 'is not in --tables list, ignoring');
      return 0;
   }

   if ( $filter->{'tables-regex'}
        && $tbl !~ $filter->{'tables-regex'} ) {
      PTDEBUG && _d('Table', $tbl, 'does not match --tables-regex, ignoring');
      return 0;
   }

   # This handles a special case like "-d d2 -t d1.t1" where the user probably
   # wants "all tables from database d1 plus table t1 from database d1."  In
   # _make_filters() we cannot add d1 to the allowed databases filter because
   # then we'll get d1 tables when the user only wants d2 tables.  So when
   # a table passes allow filters, reaching this point, meaning it is allowed,
   # we make this final to check to see if it's allowed in any database (*)
   # or allowed in the specific database that the user qualifed the table with.
   # The first two checks are to prevent auto-vivifying the filters which will
   # cause bad results (see a similar comment in _make_filters()).
   if ( $filter->{'tables'}
        && $filter->{'tables'}->{$tbl}
        && $filter->{'tables'}->{$tbl} ne '*'
        && $filter->{'tables'}->{$tbl} ne $db ) {
      PTDEBUG && _d('Table', $tbl, 'is only allowed in database',
         $filter->{'tables'}->{$tbl});
      return 0;
   }

   return 1;
}

sub engine_is_allowed {
   my ( $self, $engine ) = @_;

   if ( !$engine ) {
      # This normally doesn't happen, but it can if the user
      # is iterating a file of their own table dumps, i.e. that
      # weren't created by mysqldump, so there's no ENGINE=
      # on the CREATE TABLE.
      PTDEBUG && _d('No engine specified; allowing the table');
      return 1;
   }

   $engine = lc $engine;

   my $filter = $self->{filters};

   if ( $filter->{'ignore-engines'}->{$engine} ) {
      PTDEBUG && _d('Engine', $engine, 'is in --ignore-databases list');
      return 0;
   }

   if ( $filter->{'engines'}
        && !$filter->{'engines'}->{$engine} ) {
      PTDEBUG && _d('Engine', $engine, 'is not in --engines list, ignoring');
      return 0;
   }

   return 1;
}

sub _resume_from_database {
   my ($self, $db) = @_;

   # "Resume" from any db if we're not, in fact, resuming.
   return 1 unless $self->{resume}->{db};
   if ( $db eq $self->{resume}->{db} ) {
      if ( !$self->{resume}->{after}->{db} ) {
         PTDEBUG && _d('Resuming from db', $db);
         delete $self->{resume}->{db};
         return 1;
      }
      else {
         PTDEBUG && _d('Resuming after db', $db);
         # If we're not resuming from the resume db, then
         # we aren't resuming from the resume table either.
         delete $self->{resume}->{db};
         delete $self->{resume}->{tbl};
      }
   }

   return 0;
}

sub _resume_from_table {
   my ($self, $tbl) = @_;

   # "Resume" from any table if we're not, in fact, resuming.
   return 1 unless $self->{resume}->{tbl};

   if ( $tbl eq $self->{resume}->{tbl} ) {
      if ( !$self->{resume}->{after}->{tbl} ) {
         PTDEBUG && _d('Resuming from table', $tbl);
         delete $self->{resume}->{tbl};
         return 1;
      }
      else {
         PTDEBUG && _d('Resuming after table', $tbl);
         delete $self->{resume}->{tbl};
      }
   }

   return 0;
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
# End SchemaIterator package
# ###########################################################################

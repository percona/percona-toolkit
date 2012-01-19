# This program is copyright 2008-2011 Percona Inc.
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
# LogSplitter package
# ###########################################################################
{
# Package: LogSplitter
# LogSplitter splits MySQL query logs by sessions.
package LogSplitter;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

my $oktorun = 1;

sub new {
   my ( $class, %args ) = @_;
   foreach my $arg ( qw(attribute base_dir parser session_files) ) {
      die "I need a $arg argument" unless $args{$arg};
   }

   # TODO: this is probably problematic on Windows
   $args{base_dir} .= '/' if substr($args{base_dir}, -1, 1) ne '/';

   if ( $args{split_random} ) {
      PTDEBUG && _d('Split random');
      $args{attribute} = '_sessionno';  # set round-robin 1..session_files
   }

   my $self = {
      # %args will override these default args if given explicitly.
      base_file_name    => 'session',
      max_dirs          => 1_000,
      max_files_per_dir => 5_000,
      max_sessions      => 5_000_000,  # max_dirs * max_files_per_dir
      merge_sessions    => 1,
      session_files     => 64,
      quiet             => 0,
      verbose           => 0,
      max_open_files    => 1_000,
      close_lru_files   => 100,
      # Override default args above.
      %args,
      # These args cannot be overridden.
      n_dirs_total       => 0,  # total number of dirs created
      n_files_total      => 0,  # total number of session files created
      n_files_this_dir   => -1, # number of session files in current dir
      session_fhs        => [], # filehandles for each session
      n_open_fhs         => 0,  # current number of open session filehandles
      n_events_total     => 0,  # total number of events in log
      n_events_saved     => 0,  # total number of events saved
      n_sessions_skipped => 0,  # total number of sessions skipped
      n_sessions_saved   => 0,  # number of sessions saved
      sessions           => {}, # sessions data store
      created_dirs       => [],
   };

   PTDEBUG && _d('new LogSplitter final args:', Dumper($self));
   return bless $self, $class;
}

sub split {
   my ( $self, @logs ) = @_;
   $oktorun = 1; # True as long as we haven't created too many
                 # session files or too many dirs and files

   my $callbacks = $self->{callbacks};

   my $next_sessionno;
   if ( $self->{split_random} ) {
      # round-robin iterator
      $next_sessionno = make_rr_iter(1, $self->{session_files});
   }

   if ( @logs == 0 ) {
      PTDEBUG && _d('Implicitly reading STDIN because no logs were given');
      push @logs, '-';
   }

   # Split all the log files.
   my $lp = $self->{parser};
   LOG:
   foreach my $log ( @logs ) {
      last unless $oktorun;
      next unless defined $log;

      if ( !-f $log && $log ne '-' ) {
         warn "Skipping $log because it is not a file";
         next LOG;
      }
      my $fh;
      if ( $log eq '-' ) {
         $fh = *STDIN;
      }
      else {
         if ( !open $fh, "<", $log ) {
            warn "Cannot open $log: $OS_ERROR\n";
            next LOG;
         }
      }

      PTDEBUG && _d('Splitting', $log);
      my $event           = {};
      my $more_events     = 1;
      my $more_events_sub = sub { $more_events = $_[0]; };
      EVENT:
      while ( $oktorun ) {
         $event = $lp->parse_event(
            next_event => sub { return <$fh>;    },
            tell       => sub { return tell $fh; },
            oktorun => $more_events_sub,
         );
         if ( $event ) {
            $self->{n_events_total}++;
            if ( $self->{split_random} ) {
               $event->{_sessionno} = $next_sessionno->();
            }
            if ( $callbacks ) {
               foreach my $callback ( @$callbacks ) {
                  $event = $callback->($event);
                  last unless $event;
               }
            }
            $self->_save_event($event) if $event;
         }
         if ( !$more_events ) {
            PTDEBUG && _d('Done parsing', $log);
            close $fh;
            next LOG;
         }
         last LOG unless $oktorun;
      }
   }

   # Close session filehandles.
   while ( my $fh = pop @{ $self->{session_fhs} } ) {
      close $fh->{fh};
   }
   $self->{n_open_fhs}  = 0;

   $self->_merge_session_files() if $self->{merge_sessions};
   $self->print_split_summary() unless $self->{quiet};

   return;
}

sub _save_event {
   my ( $self, $event ) = @_; 
   my ($session, $session_id) = $self->_get_session_ds($event);
   return unless $session;

   if ( !defined $session->{fh} ) {
      $self->{n_sessions_saved}++;
      PTDEBUG && _d('New session:', $session_id, ',',
         $self->{n_sessions_saved}, 'of', $self->{max_sessions});

      my $session_file = $self->_get_next_session_file();
      if ( !$session_file ) {
         $oktorun = 0;
         PTDEBUG && _d('Not oktorun because no _get_next_session_file');
         return;
      }

      # Close Last Recently Used session fhs if opening if this new
      # session fh will cause us to have too many open files.
      if ( $self->{n_open_fhs} >= $self->{max_open_files} ) {
         $self->_close_lru_session()
      }

      # Open a fh for this session file.
      open my $fh, '>', $session_file
         or die "Cannot open session file $session_file: $OS_ERROR";
      $session->{fh} = $fh;
      $self->{n_open_fhs}++;

      # Save fh and session file in case we need to open/close it later.
      $session->{active}       = 1;
      $session->{session_file} = $session_file;

      push @{$self->{session_fhs}}, { fh => $fh, session_id => $session_id };

      PTDEBUG && _d('Created', $session_file, 'for session',
         $self->{attribute}, '=', $session_id);

      # This special comment lets mk-log-player know when a session begins.
      print $fh "-- START SESSION $session_id\n\n";
   }
   elsif ( !$session->{active} ) {
      # Reopen the existing but inactive session. This happens when
      # a new session (above) had to close LRU session fhs.

      # Again, close Last Recently Used session fhs if reopening if this
      # session's fh will cause us to have too many open files.
      if ( $self->{n_open_fhs} >= $self->{max_open_files} ) {
         $self->_close_lru_session();
      }

       # Reopen this session's fh.
       open $session->{fh}, '>>', $session->{session_file}
          or die "Cannot reopen session file "
            . "$session->{session_file}: $OS_ERROR";

       # Mark this session as active again.
       $session->{active} = 1;
       $self->{n_open_fhs}++;

       PTDEBUG && _d('Reopend', $session->{session_file}, 'for session',
         $self->{attribute}, '=', $session_id);
   }
   else {
      PTDEBUG && _d('Event belongs to active session', $session_id);
   }

   my $session_fh = $session->{fh};

   # Print USE db if 1) we haven't done so yet or 2) the db has changed.
   my $db = $event->{db} || $event->{Schema};
   if ( $db && ( !defined $session->{db} || $session->{db} ne $db ) ) {
      print $session_fh "use $db\n\n";
      $session->{db} = $db;
   }

   print $session_fh $self->flatten($event->{arg}), "\n\n";
   $self->{n_events_saved}++;

   return;
}

# Returns shortcut to session data store and id for the given event.
# The returned session will be undef if no more sessions are allowed.
sub _get_session_ds {
   my ( $self, $event ) = @_;

   my $attrib = $self->{attribute};
   if ( !$event->{ $attrib } ) {
      PTDEBUG && _d('No attribute', $attrib, 'in event:', Dumper($event));
      return;
   }

   # This could indicate a problem in parser not parsing
   # a log event correctly thereby leaving $event->{arg} undefined.
   # Or, it could simply be an event like:
   #   use db;
   #   SET NAMES utf8;
   return unless $event->{arg};

   # Don't print admin commands like quit or ping because these
   # cannot be played.
   return if ($event->{cmd} || '') eq 'Admin';

   my $session;
   my $session_id = $event->{ $attrib };

   # The following is necessary to prevent Perl from auto-vivifying
   # a lot of empty hashes for new sessions that are ignored due to
   # already having max_sessions.
   if ( $self->{n_sessions_saved} < $self->{max_sessions} ) {
      # Will auto-vivify if necessary.
      $session = $self->{sessions}->{ $session_id } ||= {};
   }
   elsif ( exists $self->{sessions}->{ $session_id } ) {
      # Use only existing sessions.
      $session = $self->{sessions}->{ $session_id };
   }
   else {
      $self->{n_sessions_skipped} += 1;
      PTDEBUG && _d('Skipping new session', $session_id,
         'because max_sessions is reached');
   }

   return $session, $session_id;
}

sub _close_lru_session {
   my ( $self ) = @_;
   my $session_fhs = $self->{session_fhs};
   my $lru_n       = $self->{n_sessions_saved} - $self->{max_open_files} - 1;
   my $close_to_n  = $lru_n + $self->{close_lru_files} - 1;

   PTDEBUG && _d('Closing session fhs', $lru_n, '..', $close_to_n,
      '(',$self->{n_sessions}, 'sessions', $self->{n_open_fhs}, 'open fhs)');

   foreach my $session ( @$session_fhs[ $lru_n..$close_to_n ] ) {
      close $session->{fh};
      $self->{n_open_fhs}--;
      $self->{sessions}->{ $session->{session_id} }->{active} = 0;
   }

   return;
}

# Returns an empty string on failure, or the next session file name on success.
# This will fail if we have opened maxdirs and maxfiles.
sub _get_next_session_file {
   my ( $self, $n ) = @_;
   return if $self->{n_dirs_total} >= $self->{max_dirs};

   # n_files_this_dir will only be < 0 for the first dir and file
   # because n_file is set to -1 in new(). This is a hack
   # to cause the first dir and file to be created automatically.
   if ( ($self->{n_files_this_dir} >= $self->{max_files_per_dir})
        || $self->{n_files_this_dir} < 0 ) {
      $self->{n_dirs_total}++;
      $self->{n_files_this_dir} = 0;
      my $new_dir = "$self->{base_dir}$self->{n_dirs_total}";
      if ( !-d $new_dir ) {
         my $retval = system("mkdir $new_dir");
         if ( ($retval >> 8) != 0 ) {
            die "Cannot create new directory $new_dir: $OS_ERROR";
         }
         PTDEBUG && _d('Created new base_dir', $new_dir);
         push @{$self->{created_dirs}}, $new_dir;
      }
      elsif ( PTDEBUG ) {
         _d($new_dir, 'already exists');
      }
   }
   else {
      PTDEBUG && _d('No dir created; n_files_this_dir:',
         $self->{n_files_this_dir}, 'n_files_total:',
         $self->{n_files_total});
   }

   $self->{n_files_total}++;
   $self->{n_files_this_dir}++;
   my $dir_n        = $self->{n_dirs_total} . '/';
   my $session_n    = sprintf '%d', $n || $self->{n_sessions_saved};
   my $session_file = $self->{base_dir}
                    . $dir_n
                    . $self->{base_file_name}."-$session_n.txt";
   PTDEBUG && _d('Next session file', $session_file);
   return $session_file;
}

# Flattens multiple new-line and spaces to single new-lines and spaces
# and remove /* comment */ blocks.
sub flatten {
   my ( $self, $query ) = @_;
   return unless $query;
   $query =~ s!/\*.*?\*/! !g;
   $query =~ s/^\s+//;
   $query =~ s/\s{2,}/ /g;
   return $query;
}

sub _merge_session_files {
   my ( $self ) = @_;

   print "Merging session files...\n" unless $self->{quiet};

   my @multi_session_files;
   for my $i ( 1..$self->{session_files} ) {
      push @multi_session_files, $self->{base_dir} ."sessions-$i.txt";
   }

   my @single_session_files = map {
      $_->{session_file};
   } values %{$self->{sessions}};

   my $i = make_rr_iter(0, $#multi_session_files);  # round-robin iterator
   foreach my $single_session_file ( @single_session_files ) {
      my $multi_session_file = $multi_session_files[ $i->() ];
      my $cmd;
      if ( $self->{split_random} ) {
         $cmd = "mv $single_session_file $multi_session_file";
      }
      else {
         $cmd = "cat $single_session_file >> $multi_session_file";
      }
      eval { `$cmd`; };
      if ( $EVAL_ERROR ) {
         warn "Failed to `$cmd`: $OS_ERROR";
      }
   }

   foreach my $created_dir ( @{$self->{created_dirs}} ) {
      my $cmd = "rm -rf $created_dir";
      eval { `$cmd`; };
      if ( $EVAL_ERROR ) {
         warn "Failed to `$cmd`: $OS_ERROR";
      }
   }

   return;
}

sub make_rr_iter {
   my ( $start, $end ) = @_;
   my $current = $start;
   return sub {
      $current = $start if $current > $end ;
      $current++;  # For next iteration.
      return $current - 1;
   };
}

sub print_split_summary {
   my ( $self ) = @_;
   print "Split summary:\n";
   my $fmt = "%-20s %-10s\n";
   printf $fmt, 'Total sessions',
      $self->{n_sessions_saved} + $self->{n_sessions_skipped};
   printf $fmt, 'Sessions saved',
      $self->{n_sessions_saved};
   printf $fmt, 'Total events', $self->{n_events_total};
   printf $fmt, 'Events saved', $self->{n_events_saved};
   return;
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
# End LogSplitter package
# ###########################################################################

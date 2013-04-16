# This program is copyright 2008-2011 Baron Schwartz, 2011 Percona Ireland Ltd.
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
# Processlist package
# ###########################################################################
{
# Package: Processlist
# Processlist makes events when used to poll SHOW FULL PROCESSLIST.
package Processlist;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Time::HiRes qw(time usleep);
use List::Util qw(max);
use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

use constant PTDEBUG => $ENV{PTDEBUG} || 0;
use constant {
   # 0-7 are the standard processlist columns.
   ID      => 0,  
   USER    => 1,  
   HOST    => 2,
   DB      => 3,
   COMMAND => 4,
   TIME    => 5,
   STATE   => 6,
   INFO    => 7,
   # 8, 9 and 10 are extra info we calculate.
   START   => 8,  # Calculated start time of statement ($start - TIME)
   ETIME   => 9,  # Exec time of SHOW PROCESSLIST (margin of error in START)
   FSEEN   => 10, # First time ever seen
   PROFILE => 11, # Profile of individual STATE times
};


# Sub: new
#
# Parameters:
#   %args - Arguments
#
# Required Arguments:
#   MasterSlave - MasterSlave obj for finding replicationt threads
#
# Optional Arguments:
#   interval - Hi-res sleep time before polling processlist in <parse_event()>.
#
# Returns:
#   Processlist object
sub new {
   my ( $class, %args ) = @_;
   foreach my $arg ( qw(MasterSlave) ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my $self = {
      %args,
      polls       => 0,
      last_poll   => 0,
      active_cxn  => {},  # keyed off ID
      event_cache => [],
      _reasons_for_matching => {},
   };
   return bless $self, $class;
}

# Sub: parse_event
#   Parse rows from PROCESSLIST to make events when queries finish.
#
# Parameters:
#   %args - Arguments
#
# Required Arguments:
#   code - Callback that returns an arrayref of rows from SHOW PROCESSLIST.
#          Replication threads and $dbh->{mysql_thread_id} should be removed
#          from the return value.
#
# Returns:
#   Hashref of a completed event.
#
# Technical Details:
#   Connections (cxn) are tracked in a hashref ($self->{active_cxn}) by their
#   Id from the proclist.  Each poll of the proclist (i.e. each call to the
#   code callback) causes the current cxn/queries to be compared to the saved
#   (active) cxn. One of three things can happen: a new cxn appears, a query
#   ends/changes/restarts, or a cxn ends (and thus ends its query).
#
#   When a new connect appears, we only begin tracking it when the Info column
#   from the proclist is not null, indicating that the cxn is executing a
#   query.  The full proclist for this cxn is saved for comparison with later
#   polls.  This is $prev in the code which really references
#   $self->{active_cxn}.
#
#   For existing cxn, if the Info is the same (i.e. same query), and the Time
#   hasn't decreased, and the query hasn't restarted (look below in the code
#   for how we detect this), then the cxn is still executing the same query.
#   So we do nothing.  But if any one of those 3 conditions is false, that
#   signals a new query.  So we make an event based on saved info from the
#   last poll, then updated the cxn for the new query already in progress.
#
#   When a previously active cxn no longer appears in a poll, then that cxn
#   has ended and so did it's query, so we make an event for the query and
#   then delete the cxn from $self->{active_cxn}.  This is checked in the
#   PREVIOUSLY_ACTIVE_CXN loop.
#
#   The default MySQL server has one-second granularity in the Time column.
#   This means that a statement that starts at X.9 seconds shows 0 seconds
#   for only 0.1 second.  A statement that starts at X.0 seconds shows 0 secs
#   for a second, and 1 second up until it has actually been running 2 seconds.
#   This makes it tricky to determine when a statement has been restarted.
#   Further, this program and MySQL may have some clock skew.  Even if they
#   are running on the same machine, it's possible that at X.999999 seconds
#   we get the time, and at X+1.000001 seconds we get the snapshot from MySQL.
#   (Fortunately MySQL doesn't re-evaluate now() for every process, or that
#   would cause even more problems.)  And a query that's issued to MySQL may
#   stall for any amount of time before it's executed, making even more skew
#   between the times.
#
#   One worst case is,
#     * The processlist measures time at 100.01 and it's 100.
#     * We measure the time.  It says 100.02.
#     * A query was started at 90.  Processlist says Time=10.
#     * We calculate that the query was started at 90.02.
#     * Processlist measures it at 100.998 and it's 100.
#     * We measure time again, it says 100.999.
#     * Time has passed, but the Time column still says 10.
#
#   Another is,
#     * We get the processlist, then the time.
#     * A second later we get the processlist, but it takes 2 sec to fetch.
#     * We measure the time and it looks like 3 sec have passed, but proclist
#       says only one has passed.  This is why etime is necessary.
#   What should we do?  Well, the key thing to notice here is that a new
#   statement has started if a) the Time column actually decreases since we
#   last saw the process, or b) the Time column does not increase for 2
#   seconds, plus the etime of the first and second measurements combined!
sub parse_event {
   my ( $self, %args ) = @_;
   my @required_args = qw(code);
   foreach my $arg ( @required_args ) {
     die "I need a $arg argument" unless $args{$arg};
   }
   my ($code) = @args{@required_args};

   # Our first priority is to return cached events.  The caller expects
   # one event per return so we have to cache our events.  And the caller
   # should accept events as fast as we can return them; i.e. the caller
   # should not sleep between polls--that's our job in here (below).
   # XXX: This should only cause a problem if the caller is really slow
   # between calls to us, in which case polling may be delayed by the
   # caller's slowness plus our interval sleep.
   if ( @{$self->{event_cache}} ) {
      PTDEBUG && _d("Returning cached event");
      return shift @{$self->{event_cache}};
   }

   # It's time to sleep if we want to sleep and this is not the first poll.
   # Again, this assumes that the caller is not sleeping before calling us
   # and is not really slow between calls.  By "really slow" I mean slower
   # than the interval time.
   if ( $self->{interval} && $self->{polls} ) {
      PTDEBUG && _d("Sleeping between polls");
      usleep($self->{interval});
   }

   # Poll the processlist and time how long this takes.  Also get
   # the current time and calculate the poll time (etime) unless
   # these values are given via %args (for testing).
   # $time is the time after the poll so that $time-TIME should equal
   # the query's real start time, but see $query_start below...
   PTDEBUG && _d("Polling PROCESSLIST");
   my ($time, $etime) = @args{qw(time etime)};
   my $start          = $etime ? 0 : time;  # don't need start if etime given
   my $rows           = $code->();
   if ( !$rows ) {
      warn "Processlist callback did not return an arrayref";
      return;
   }
   $time  = time           unless $time;
   $etime = $time - $start unless $etime;
   $self->{polls}++;
   PTDEBUG && _d('Rows:', ($rows ? scalar @$rows : 0), 'in', $etime, 'seconds');

   my $active_cxn = $self->{active_cxn};
   my $curr_cxn   = {};
   my @new_cxn    = ();

   # First look at each currently active process/cxn in the processlist.
   # From these we can determine:
   #   1. If any of our previously active cxn are still active.
   #   2. If there's any new cxn.
   CURRENTLY_ACTIVE_CXN:
   foreach my $curr ( @$rows ) {

      # Each currently active cxn is saved so we can later determine
      # (3) if any previously active cxn ended.
      $curr_cxn->{$curr->[ID]} = $curr;

      # $time - TIME should equal the query's real start time, but since
      # the poll may be delayed, the more-precise start time is
      # $time - $etime - TIME; that is, we compensate $time for the amount
      # of $etime we were delay before MySQL returned us the proclist rows,
      # *But*, we only compensate with $etime for the restart check below
      # because otherwise the start time just becomes the event's ts and
      # that doesn't need to be so precise.
      my $query_start = $time - ($curr->[TIME] || 0);

      if ( $active_cxn->{$curr->[ID]} ) {
         PTDEBUG && _d('Checking existing cxn', $curr->[ID]);
         my $prev      = $active_cxn->{$curr->[ID]}; # previous state of cxn
         my $new_query = 0;
         my $fudge     = ($curr->[TIME] || 0) =~ m/\D/ ? 0.001 : 1; # micro-t?

         # If this is true, then the cxn was executing a query last time
         # we saw it.  Determine if the cxn is executing a new query.
         if ( $prev->[INFO] ) {
            if ( !$curr->[INFO] || $prev->[INFO] ne $curr->[INFO] ) {
               # This is a new/different query because what's currently
               # executing is different from what the cxn was previously
               # executing.
               PTDEBUG && _d('Info is different; new query');
               $new_query = 1;
            }
            elsif ( defined $curr->[TIME] && $curr->[TIME] < $prev->[TIME] ) {
               # This is a new/different query because the current exec
               # time is less than the previous exec time, so the previous
               # query ended and a new one began between polls.
               PTDEBUG && _d('Time is less than previous; new query');
               $new_query = 1;
            }
            elsif ( $curr->[INFO] && defined $curr->[TIME]
                    && $query_start - $etime - $prev->[START] > $fudge)
            {
               # If the query's recalculated start time minus its previously
               # calculated start time is greater than the fudge factor, then
               # the query has restarted.  I.e. the new start time is after
               # the previous start time.
               my $ms = $self->{MasterSlave};
               
               my $is_repl_thread = $ms->is_replication_thread({
                                        Command => $curr->[COMMAND],
                                        User    => $curr->[USER],
                                        State   => $curr->[STATE],
                                        Id      => $curr->[ID]});
               if ( $is_repl_thread ) {
                  PTDEBUG &&
                  _d(q{Query has restarted but it's a replication thread, ignoring});
               }
               else {
                  PTDEBUG && _d('Query restarted; new query',
                     $query_start, $etime, $prev->[START], $fudge);
                  $new_query = 1;
               }
            }

            if ( $new_query ) {
               # The cxn is executing a new query, so the previous query
               # ended.  Make an event for the previous query.
               $self->_update_profile($prev, $curr, $time);
               push @{$self->{event_cache}},
                  $self->make_event($prev, $time);
            }
         }

         # If this is true, the cxn is currently executing a query.
         # Determine if that query is old (i.e. same one running previously),
         # or new.  In either case, we save it to recheck it next poll.
         if ( $curr->[INFO] ) {
            if ( $prev->[INFO] && !$new_query ) {
               PTDEBUG && _d("Query on cxn", $curr->[ID], "hasn't changed");
               $self->_update_profile($prev, $curr, $time);
            }
            else {
               PTDEBUG && _d('Saving new query, state', $curr->[STATE]);
               push @new_cxn, [
                  @{$curr}[0..7],           # proc info
                  int($query_start),        # START
                  $etime,                   # ETIME
                  $time,                    # FSEEN
                  { ($curr->[STATE] || "") => 0 }, # PROFILE
               ];
            }
         }
      } 
      else {
         PTDEBUG && _d('New cxn', $curr->[ID]);
         if ( $curr->[INFO] && defined $curr->[TIME] ) {
            # But only save the new cxn if it's executing.
            PTDEBUG && _d('Saving query of new cxn, state', $curr->[STATE]);
            push @new_cxn, [
               @{$curr}[0..7],           # proc info
               int($query_start),        # START
               $etime,                   # ETIME
               $time,                    # FSEEN
               { ($curr->[STATE] || "") => 0 }, # PROFILE
            ];
         }
      }
   }  # CURRENTLY_ACTIVE_CXN

   # Look at the cxn that we think are active.  From these we can
   # determine:
   #   3. If any of them ended.
   # For the moment, "ended" means "not executing a query".  Later
   # we may track a cxn in its entirety for quasi-profiling.
   PREVIOUSLY_ACTIVE_CXN:
   foreach my $prev ( values %$active_cxn ) {
      if ( !$curr_cxn->{$prev->[ID]} ) {
         PTDEBUG && _d('cxn', $prev->[ID], 'ended');
         push @{$self->{event_cache}},
            $self->make_event($prev, $time);
         delete $active_cxn->{$prev->[ID]};
      }
      elsif (   ($curr_cxn->{$prev->[ID]}->[COMMAND] || "") eq 'Sleep' 
             || !$curr_cxn->{$prev->[ID]}->[STATE]
             || !$curr_cxn->{$prev->[ID]}->[INFO] ) {
         PTDEBUG && _d('cxn', $prev->[ID], 'became idle');
         # We do not make an event in this case because it will have
         # already been made above because of the INFO change.  But
         # until we begin tracking cxn in their entirety, we do not
         # to save idle cxn to save memory.
         delete $active_cxn->{$prev->[ID]};
      }
   }

   # Finally, merge new cxn into our hashref of active cxn.
   # This is done here and not when the new cnx are discovered
   # so that the PREVIOUSLY_ACTIVE_CXN doesn't look at them.
   map { $active_cxn->{$_->[ID]} = $_; } @new_cxn;

   $self->{last_poll} = $time;

   # Return the first event in our cache, if any.  It may be an event
   # we just made, or an event from a previous call.
   my $event = shift @{$self->{event_cache}};
   PTDEBUG && _d(scalar @{$self->{event_cache}}, "events in cache");
   return $event;
}

# The exec time of the query is the max of the time from the processlist, or the
# time during which we've actually observed the query running.  In case two
# back-to-back queries executed as the same one and we weren't able to tell them
# apart, their time will add up, which is kind of what we want.
sub make_event {
   my ( $self, $row, $time ) = @_;

   my $observed_time = $time - $row->[FSEEN];
   my $Query_time    = max($row->[TIME], $observed_time);

   # An alternative to the above.
   # my $observed_time = $self->{last_poll} - $row->[FSEEN];
   # my $Query_time    = max($row->[TIME], $observed_time);

   # Another alternative for this issue:
   # http://code.google.com/p/maatkit/issues/detail?id=1246
   # my $interval      = $time - $self->{last_poll};
   # my $observed_time = ($self->{last_poll} + ($interval/2)) - $row->[FSEEN];
   # my $Query_time    = max($row->[TIME], $observed_time);

   # Slowlog Query_time includes Lock_time and we emulate this, too, but
   # *not* by adding $row->[PROFILE]->{Locked} to $Query_time because
   # our query time is already inclusive since we track query time based on
   # INFO not STATE.  So our query time might be too inclusive since it
   # includes any and all states of the query during its execution.

   my $event = {
      id         => $row->[ID],
      db         => $row->[DB],
      user       => $row->[USER],
      host       => $row->[HOST],
      arg        => $row->[INFO],
      bytes      => length($row->[INFO]),
      ts         => Transformers::ts($row->[START] + $row->[TIME]), # Query END time
      Query_time => $Query_time,
      Lock_time  => $row->[PROFILE]->{Locked} || 0,
   };
   PTDEBUG && _d('Properties of event:', Dumper($event));
   return $event;
}

sub _get_active_cxn {
   my ( $self ) = @_;
   PTDEBUG && _d("Active cxn:", Dumper($self->{active_cxn}));
   return $self->{active_cxn};
}

# Sub: _update_profile
#   Update a query's PROFILE of STATE times.  The given cxn arrayrefs
#   ($prev and $curr) should be the same cxn and same query.  If the
#   query' state hasn't changed, the current state's time is incremented
#   by time elapsed between the last poll and now now ($time).  Else,
#   half the elapsed time is added to the previous state and half to the
#   current state (re issue 1246).
#
#   We cannot calculate a START for any state because the query's TIME
#   covers all states, so there's no way a posteriori to know how much
#   of TIME was spent in any given state.  The best we can do is count
#   how long we see the query in each state where ETIME (poll time)
#   defines our resolution.
#
# Parameters:
#   $prev - Arrayref of cxn's previous info
#   $curr - Arrayref of cxn's current info
#   $time - Current time (taken after poll)
sub _update_profile {
   my ( $self, $prev, $curr, $time ) = @_;
   return unless $prev && $curr;

   my $time_elapsed = $time - $self->{last_poll};

   # Update only $prev because the caller should only be saving that arrayref.

   if ( ($prev->[STATE] || "") eq ($curr->[STATE] || "") ) {
      PTDEBUG && _d("Query is still in", $curr->[STATE], "state");
      $prev->[PROFILE]->{$prev->[STATE] || ""} += $time_elapsed;
   }
   else {
      # XXX The State of this cxn changed between polls.  How long
      # was it in its previous state, and how long has it been in
      # its current state?  We can't tell, so this is a compromise
      # re http://code.google.com/p/maatkit/issues/detail?id=1246
      PTDEBUG && _d("Query changed from state", $prev->[STATE],
         "to", $curr->[STATE]);
      my $half_time = ($time_elapsed || 0) / 2;

      # Previous state ends.
      $prev->[PROFILE]->{$prev->[STATE] || ""} += $half_time;

      # Query assumes new state and we presume that the query has been
      # in that state for half the poll time.
      $prev->[STATE] = $curr->[STATE];
      $prev->[PROFILE]->{$curr->[STATE] || ""}  = $half_time;
   }

   return;
}

# Accepts a PROCESSLIST and a specification of filters to use against it.
# Returns queries that match the filters.  The standard process properties
# are: Id, User, Host, db, Command, Time, State, Info.  These are used for
# ignore and match.
#
# Possible find_spec are:
#   * all            Match all not-ignored queries
#   * busy_time      Match queries that have been Command=Query for longer than
#                    this time
#   * idle_time      Match queries that have been Command=Sleep for longer than
#                    this time
#   * ignore         A hashref of properties => regex patterns to ignore
#   * match          A hashref of properties => regex patterns to match
#
sub find {
   my ( $self, $proclist, %find_spec ) = @_;
   PTDEBUG && _d('find specs:', Dumper(\%find_spec));
   my $ms  = $self->{MasterSlave};

   my @matches;
   QUERY:
   foreach my $query ( @$proclist ) {
      PTDEBUG && _d('Checking query', Dumper($query));
      my $matched = 0;

      # Don't allow matching replication threads.
      if (    !$find_spec{replication_threads}
           && $ms->is_replication_thread($query) ) {
         PTDEBUG && _d('Skipping replication thread');
         next QUERY;
      }

      # Match special busy_time.
      if ( $find_spec{busy_time} && ($query->{Command} || '') eq 'Query' ) {
         next QUERY unless defined($query->{Time});
         if ( $query->{Time} < $find_spec{busy_time} ) {
            PTDEBUG && _d("Query isn't running long enough");
            next QUERY;
         }
         my $reason = 'Exceeds busy time';
         PTDEBUG && _d($reason);
         # Saving the reasons for each query in the objct is a bit nasty,
         # but the alternatives are worse:
         # - Saving internal data in the query
         # - Instead of using the stringified hashref as a key, using
         #   a checksum of the hashes' contents. Which could occasionally
         #   fail miserably due to timing-related issues.
         push @{$self->{_reasons_for_matching}->{$query} ||= []}, $reason;
         $matched++;
      }

      # Match special idle_time.
      if ( $find_spec{idle_time} && ($query->{Command} || '') eq 'Sleep' ) {
         next QUERY unless defined($query->{Time});
         if ( $query->{Time} < $find_spec{idle_time} ) {
            PTDEBUG && _d("Query isn't idle long enough");
            next QUERY;
         }
         my $reason = 'Exceeds idle time';
         PTDEBUG && _d($reason);
         push @{$self->{_reasons_for_matching}->{$query} ||= []}, $reason;
         $matched++;
      }
 
      PROPERTY:
      foreach my $property ( qw(Id User Host db State Command Info) ) {
         my $filter = "_find_match_$property";
         # Check ignored properties first.  If the proc has at least one
         # property that matches an ignore value, then it is totally ignored.
         # and we can skip to the next proc (query).
         if ( defined $find_spec{ignore}->{$property}
              && $self->$filter($query, $find_spec{ignore}->{$property}) ) {
            PTDEBUG && _d('Query matches ignore', $property, 'spec');
            next QUERY;
         }
         # If the proc's property value isn't ignored, then check if it matches.
         if ( defined $find_spec{match}->{$property} ) {
            if ( !$self->$filter($query, $find_spec{match}->{$property}) ) {
               PTDEBUG && _d('Query does not match', $property, 'spec');
               next QUERY;
            }
            my $reason = 'Query matches ' . $property . ' spec';
            PTDEBUG && _d($reason);
            push @{$self->{_reasons_for_matching}->{$query} ||= []}, $reason;
            $matched++;
         }
      }
      if ( $matched || $find_spec{all} ) {
         PTDEBUG && _d("Query matched one or more specs, adding");
         push @matches, $query;
         next QUERY;
      }
      PTDEBUG && _d('Query does not match any specs, ignoring');
   } # QUERY

   return @matches;
}

sub _find_match_Id {
   my ( $self, $query, $property ) = @_;
   return defined $property && defined $query->{Id} && $query->{Id} == $property;
}

sub _find_match_User {
   my ( $self, $query, $property ) = @_;
   return defined $property && defined $query->{User}
      && $query->{User} =~ m/$property/;
}

sub _find_match_Host {
   my ( $self, $query, $property ) = @_;
   return defined $property && defined $query->{Host}
      && $query->{Host} =~ m/$property/;
}

sub _find_match_db {
   my ( $self, $query, $property ) = @_;
   return defined $property && defined $query->{db}
      && $query->{db} =~ m/$property/;
}

sub _find_match_State {
   my ( $self, $query, $property ) = @_;
   return defined $property && defined $query->{State}
      && $query->{State} =~ m/$property/;
}

sub _find_match_Command {
   my ( $self, $query, $property ) = @_;
   return defined $property && defined $query->{Command}
      && $query->{Command} =~ m/$property/;
}

sub _find_match_Info {
   my ( $self, $query, $property ) = @_;
   return defined $property && defined $query->{Info}
      && $query->{Info} =~ m/$property/;
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
# End Processlist package
# ###########################################################################

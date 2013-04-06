# This program is copyright 2008-2013 Percona Ireland Ltd.
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
# Daemon package
# ###########################################################################
package Daemon;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);

use constant PTDEBUG => $ENV{PTDEBUG} || 0;

use POSIX qw(setsid);
use Fcntl qw(:DEFAULT);

sub new {
   my ($class, %args) = @_;
   my $self = {
      log_file       => $args{log_file},
      pid_file       => $args{pid_file},
      daemonize      => $args{daemonize},
      force_log_file => $args{force_log_file},
      parent_exit    => $args{parent_exit},
      pid_file_owner => 0,
   };
   return bless $self, $class;
}

sub run {
   my ($self) = @_;

   # Just for brevity:
   my $daemonize      = $self->{daemonize};
   my $pid_file       = $self->{pid_file};
   my $log_file       = $self->{log_file};
   my $force_log_file = $self->{force_log_file};
   my $parent_exit    = $self->{parent_exit};

   PTDEBUG && _d('Starting daemon');

   # First obtain the pid file or die trying.  NOTE: we're still the parent
   # so the pid file will contain the parent's pid at first.  This is done
   # to avoid a race condition between the parent checking for the pid file,
   # forking, and the child actually obtaining the pid file.  This way, if
   # the parent obtains the pid file, the child is guaranteed to be the only
   # process running.
   if ( $pid_file ) {
      eval {
         $self->_make_pid_file(
            pid      => $PID,  # parent's pid
            pid_file => $pid_file,
         );
      };
      die "$EVAL_ERROR\n" if $EVAL_ERROR;
      if ( !$daemonize ) {
         # We're not going to daemonize, so mark the pid file as owned
         # by the parent.  Otherwise, daemonize/fork and the child will
         # take ownership.
         $self->{pid_file_owner} = $PID;  # parent's pid
      }
   }

   # Fork, exit parent, continue as child process.
   if ( $daemonize ) {
      defined (my $child_pid = fork()) or die "Cannot fork: $OS_ERROR";
      if ( $child_pid ) {
         # I'm the parent.
         PTDEBUG && _d('Forked child', $child_pid);
         $parent_exit->($child_pid) if $parent_exit;
         exit 0;
      }
 
      # I'm the child. 
      POSIX::setsid() or die "Cannot start a new session: $OS_ERROR";
      chdir '/'       or die "Cannot chdir to /: $OS_ERROR";

      # Now update the pid file to contain the child's pid.
      if ( $pid_file ) {
         $self->_update_pid_file(
            pid      => $PID,  # child's pid
            pid_file => $pid_file,
         );
         $self->{pid_file_owner} = $PID;
      }
   }

   if ( $daemonize || $force_log_file ) {
      # We used to only reopen STDIN to /dev/null if it's a tty because
      # otherwise it may be a pipe, in which case we didn't want to break
      # it.  However, Perl -t is not reliable.  This is true and false on
      # various boxes even when the same code is ran, or it depends on if
      # the code is ran via cron, Jenkins, etc.  Since there should be no
      # sane reason to `foo | pt-tool --daemonize` for a tool that reads
      # STDIN, we now just always close STDIN.
      PTDEBUG && _d('Redirecting STDIN to /dev/null');
      close STDIN;
      open  STDIN, '/dev/null'
         or die "Cannot reopen STDIN to /dev/null: $OS_ERROR";
      if ( $log_file ) {
         PTDEBUG && _d('Redirecting STDOUT and STDERR to', $log_file);
         close STDOUT;
         open  STDOUT, '>>', $log_file
            or die "Cannot open log file $log_file: $OS_ERROR";

         # If we don't close STDERR explicitly, then prove Daemon.t fails
         # because STDERR gets written before STDOUT even though we print
         # to STDOUT first in the tests.  I don't know why, but it's probably
         # best that we just explicitly close all fds before reopening them.
         close STDERR;
         open  STDERR, ">&STDOUT"
            or die "Cannot dupe STDERR to STDOUT: $OS_ERROR"; 
      }
      else {
         if ( -t STDOUT ) {
            PTDEBUG && _d('No log file and STDOUT is a terminal;',
               'redirecting to /dev/null');
            close STDOUT;
            open  STDOUT, '>', '/dev/null'
               or die "Cannot reopen STDOUT to /dev/null: $OS_ERROR";
         }
         if ( -t STDERR ) {
            PTDEBUG && _d('No log file and STDERR is a terminal;',
               'redirecting to /dev/null');
            close STDERR;
            open  STDERR, '>', '/dev/null'
               or die "Cannot reopen STDERR to /dev/null: $OS_ERROR";
         }
      }

      $OUTPUT_AUTOFLUSH = 1;
   }

   PTDEBUG && _d('Daemon running');
   return;
}

# Call this for non-daemonized scripts to make a PID file.
sub _make_pid_file {
   my ($self, %args) = @_;
   my @required_args = qw(pid pid_file);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   };
   my $pid      = $args{pid};
   my $pid_file = $args{pid_file};

   # "If O_CREAT and O_EXCL are set, open() shall fail if the file exists.
   #  The check for the existence of the file and the creation of the file
   #  if it does not exist shall be atomic with respect to other threads
   #  executing open() naming the same filename in the same directory with
   #  O_EXCL and O_CREAT set.
   eval {
      sysopen(PID_FH, $pid_file, O_RDWR|O_CREAT|O_EXCL) or die $OS_ERROR;
      print PID_FH $PID, "\n";
      close PID_FH; 
   };
   if ( my $e = $EVAL_ERROR ) {
      if ( $e =~ m/file exists/i ) {
         # Check if the existing pid is running.  If yes, then die,
         # else this returns and we overwrite the pid file.
         my $old_pid = $self->_check_pid_file(
            pid_file => $pid_file,
            pid      => $PID,
         );
         if ( $old_pid ) {
            warn "Overwriting PID file $pid_file because PID $old_pid "
               . "is not running.\n";
         }
         $self->_update_pid_file(
            pid      => $PID,
            pid_file => $pid_file
         );
      }
      else {
         die "Error creating PID file $pid_file: $e\n";
      }
   }

   return;
}

sub _check_pid_file {
   my ($self, %args) = @_;
   my @required_args = qw(pid_file pid);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   };
   my $pid_file = $args{pid_file};
   my $pid      = $args{pid};

   PTDEBUG && _d('Checking if PID in', $pid_file, 'is running');

   if ( ! -f $pid_file ) {
      PTDEBUG && _d('PID file', $pid_file, 'does not exist');
      return;
   }

   open my $fh, '<', $pid_file
      or die "Error opening $pid_file: $OS_ERROR";
   my $existing_pid = do { local $/; <$fh> };
   chomp($existing_pid) if $existing_pid;
   close $fh
      or die "Error closing $pid_file: $OS_ERROR";

   if ( $existing_pid ) {
      if ( $existing_pid == $pid ) {
         # This happens when pt-agent "re-daemonizes".
         warn "The current PID $pid already holds the PID file $pid_file\n";
         return;
      }
      else {
         PTDEBUG && _d('Checking if PID', $existing_pid, 'is running');
         my $pid_is_alive = kill 0, $existing_pid;
         if ( $pid_is_alive ) {
            die "PID file $pid_file exists and PID $existing_pid is running\n";
         }
      }
   }
   else {
      # PID file but no PID: not sure what to do, so be safe and die;
      # let the user figure it out (i.e. rm the pid file).
      die "PID file $pid_file exists but it is empty.  Remove the file "
         . "if the process is no longer running.\n";
   }

   return $existing_pid;
}

sub _update_pid_file {
   my ($self, %args) = @_;
   my @required_args = qw(pid pid_file);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   };
   my $pid      = $args{pid};
   my $pid_file = $args{pid_file};

   open my $fh, '>', $pid_file
      or die "Cannot open $pid_file: $OS_ERROR";
   print { $fh } $pid, "\n"
      or die "Cannot print to $pid_file: $OS_ERROR";
   close $fh
      or warn "Cannot close $pid_file: $OS_ERROR";

   return;
}

sub remove_pid_file {
   my ($self, $pid_file) = @_;
   $pid_file ||= $self->{pid_file};
   if ( $pid_file && -f $pid_file ) {
      unlink $self->{pid_file}
         or warn "Cannot remove PID file $pid_file: $OS_ERROR";
      PTDEBUG && _d('Removed PID file');
   }
   else {
      PTDEBUG && _d('No PID to remove');
   }
   return;
}

sub DESTROY {
   my ($self) = @_;

   # Remove the PID file only if we created it.  There's two cases where
   # it might be removed wrongly.  1) When the obj first daemonizes itself,
   # the parent's copy of the obj will call this sub when it exits.  We
   # don't remove it then because the child that continues to run won't
   # have it.  2) When daemonized code forks its children get copies of
   # the Daemon obj which will also call this sub when they exit.  We
   # don't remove it then because the daemonized parent code won't have it.
   # This trick works because $self->{pid_file_owner}=$PID is set once to the
   # owner's $PID then this value is copied on fork.  But the "== $PID"
   # here is the forked copy's PID which won't match the owner's PID.
   if ( $self->{pid_file_owner} == $PID ) {
      $self->remove_pid_file();
   }

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
# ###########################################################################
# End Daemon package
# ###########################################################################

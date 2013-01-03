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
# MemcachedEvent package
# ###########################################################################
{
# Package: MemcachedEvent
# MemcachedEvent creates events from <MemcachedProtocolParser> data.
# Since memcached is not strictly MySQL stuff, we have to
# fabricate MySQL-like query events from memcached.
# 
# See http://code.sixapart.com/svn/memcached/trunk/server/doc/protocol.txt
# for information about the memcached protocol.
package MemcachedEvent;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

# cmds that we know how to handle.
my %cmds = map { $_ => 1 } qw(
   set
   add
   replace
   append
   prepend
   cas
   get
   gets
   delete
   incr
   decr
);

my %cmd_handler_for = (
   set      => \&handle_storage_cmd,
   add      => \&handle_storage_cmd,
   replace  => \&handle_storage_cmd,
   append   => \&handle_storage_cmd,
   prepend  => \&handle_storage_cmd,
   cas      => \&handle_storage_cmd,
   get      => \&handle_retr_cmd,
   gets     => \&handle_retr_cmd,
);

sub new {
   my ( $class, %args ) = @_;
   my $self = {};
   return bless $self, $class;
}

# Given an event from MemcachedProtocolParser, returns an event
# more suitable for mk-query-digest.
sub parse_event {
   my ( $self, %args ) = @_;
   my $event = $args{event};
   return unless $event;

   if ( !$event->{cmd} || !$event->{key} ) {
      PTDEBUG && _d('Event has no cmd or key:', Dumper($event));
      return;
   }

   if ( !$cmds{$event->{cmd}} ) {
      PTDEBUG && _d("Don't know how to handle cmd:", $event->{cmd});
      return;
   }

   # For a normal event, arg is the query.  For memcached, the "query" is
   # essentially the cmd and key, so this becomes arg.  E.g.: "set mk_key".
   $event->{arg}         = "$event->{cmd} $event->{key}";
   $event->{fingerprint} = $self->fingerprint($event->{arg});
   $event->{key_print}   = $self->fingerprint($event->{key});

   # Set every cmd so that aggregated totals will be correct.  If we only
   # set cmd that we get, then all cmds will show as 100% in the report.
   # This will create a lot of 0% cmds, but --[no]zero-bool will remove them.
   # Think of events in a Percona-patched log: the attribs like Full_scan are
   # present for every event.
   map { $event->{"Memc_$_"} = 'No' } keys %cmds;
   $event->{"Memc_$event->{cmd}"} = 'Yes';  # Got this cmd.
   $event->{Memc_error}           = 'No';  # A handler may change this.
   $event->{Memc_miss}            = 'No';
   if ( $event->{res} ) {
      $event->{Memc_miss}         = 'Yes' if $event->{res} eq 'NOT_FOUND';
   }
   else {
      # This normally happens with incr and decr cmds.
      PTDEBUG && _d('Event has no res:', Dumper($event));
   }

   # Handle special results, errors, etc.  The handler should return the
   # event on success, or nothing on failure.
   if ( $cmd_handler_for{$event->{cmd}} ) {
      return $cmd_handler_for{$event->{cmd}}->($event);
   }

   return $event;
}

# Replace things that look like placeholders with a ?
sub fingerprint {
   my ( $self, $val ) = @_;
   $val =~ s/[0-9A-Fa-f]{16,}|\d+/?/g;
   return $val;
}

# Possible results for storage cmds:
# - "STORED\r\n", to indicate success.
#
# - "NOT_STORED\r\n" to indicate the data was not stored, but not
#   because of an error. This normally means that either that the
#   condition for an "add" or a "replace" command wasn't met, or that the
#   item is in a delete queue (see the "delete" command below).
#
# - "EXISTS\r\n" to indicate that the item you are trying to store with
#   a "cas" command has been modified since you last fetched it.
#
# - "NOT_FOUND\r\n" to indicate that the item you are trying to store
#   with a "cas" command did not exist or has been deleted.
sub handle_storage_cmd {
   my ( $event ) = @_;

   # There should be a result for any storage cmd.   
   if ( !$event->{res} ) {
      PTDEBUG && _d('No result for event:', Dumper($event));
      return;
   }

   $event->{'Memc_Not_Stored'} = $event->{res} eq 'NOT_STORED' ? 'Yes' : 'No';
   $event->{'Memc_Exists'}     = $event->{res} eq 'EXISTS'     ? 'Yes' : 'No';

   return $event;
}

# Technically, the only results for a retrieval cmd are the values requested.
#  "If some of the keys appearing in a retrieval request are not sent back
#   by the server in the item list this means that the server does not
#   hold items with such keys (because they were never stored, or stored
#   but deleted to make space for more items, or expired, or explicitly
#   deleted by a client)."
# Contrary to this, MemcacedProtocolParser will set res='VALUE' on
# success, res='NOT_FOUND' on failure, or res='INTERRUPTED' if the get
# didn't finish.
sub handle_retr_cmd {
   my ( $event ) = @_;

   # There should be a result for any retr cmd.   
   if ( !$event->{res} ) {
      PTDEBUG && _d('No result for event:', Dumper($event));
      return;
   }

   $event->{'Memc_error'} = $event->{res} eq 'INTERRUPTED' ? 'Yes' : 'No';

   return $event;
}

# handle_delete() and handle_incr_decr_cmd() are stub subs in case we
# need them later.

# Possible results for a delete cmd:
# - "DELETED\r\n" to indicate success
#
# - "NOT_FOUND\r\n" to indicate that the item with this key was not
#   found.
sub handle_delete {
   my ( $event ) = @_;
   return $event;
}

# Possible results for an incr or decr cmd:
# - "NOT_FOUND\r\n" to indicate the item with this value was not found
#
# - <value>\r\n , where <value> is the new value of the item's data,
#   after the increment/decrement operation was carried out.
# On success, MemcachedProtocolParser sets res='' and val=the new val.
# On failure, res=the result and val=''.
sub handle_incr_decr_cmd {
   my ( $event ) = @_;
   return $event;
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
# End MemcachedEvent package
# ###########################################################################

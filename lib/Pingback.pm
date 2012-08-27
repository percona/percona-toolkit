# This program is copyright 2012 Percona Inc.
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
# VersionCheck package
# ###########################################################################
{
# Package: Pingback
# Pingback gets and reports program versions to Percona.
package Pingback;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);

use constant PTDEBUG => $ENV{PTDEBUG} || 0;

use Data::Dumper   qw();
use Digest::MD5    qw(md5_hex);
use Sys::Hostname  qw(hostname);
use Fcntl          qw(:DEFAULT);
use File::Basename qw();
use File::Spec;

my $dir              = File::Spec->tmpdir();
my $check_time_file  = File::Spec->catfile($dir,'percona-toolkit-version-check');
my $check_time_limit = 60 * 60 * 24;  # one day

sub Dumper {
   local $Data::Dumper::Indent    = 1;
   local $Data::Dumper::Sortkeys  = 1;
   local $Data::Dumper::Quotekeys = 0;

   Data::Dumper::Dumper(@_);
}

local $EVAL_ERROR;
eval {
   require Percona::Toolkit;
   require HTTPMicro;
   require VersionCheck;
};

sub version_check {
   my @instances = @_;
   # If this blows up, oh well, don't bother the user about it.
   # This feature is a "best effort" only; we don't want it to
   # get in the way of the tool's real work.
   eval {
      if (exists $ENV{PERCONA_VERSION_CHECK} && !$ENV{PERCONA_VERSION_CHECK}) {
         if ( $ENV{PTVCDEBUG} || PTDEBUG ) {
            _d('--version-check is disabled by the PERCONA_VERSION_CHECK',
               'environment variable');
         }
         return;
      } 

      my %id_to_dbh  = map { _generate_identifier($_) => $_->{dbh} } @instances;
      my $time_to_check = time_to_check($check_time_file, [ keys %id_to_dbh ]);
      if ( !$time_to_check ) {
         if ( $ENV{PTVCDEBUG} || PTDEBUG ) {
            _d('It is not time to --version-check again;',
               'only 1 check per', $check_time_limit, 'seconds, and the last',
               'check was performed on the modified time of', $check_time_file);
         }
         return;
      }

      my $instances_to_check = ref($time_to_check)
                             ? { map { $_ => $id_to_dbh{$_} } @$time_to_check }
                             : {};
      my $advice = pingback(
         url       => $ENV{PERCONA_VERSION_CHECK_URL} || 'http://v.percona.com',
         instances => $instances_to_check,
      );
      if ( $advice ) {
         print "# Percona suggests these upgrades:\n";
         print join("\n", map { "#   * $_" } @$advice);
         print "\n# Specify --no-version-check to disable these suggestions.\n\n";
      }
      elsif ( $ENV{PTVCDEBUG} || PTDEBUG ) {
         _d('--version-check worked, but there were no suggestions');
      }
   };
   if ( $EVAL_ERROR ) {
      if ( $ENV{PTVCDEBUG} || PTDEBUG ) {
         _d('Error doing --version-check:', $EVAL_ERROR);
      }
   }

   return;
}

sub pingback {
   my (%args) = @_;
   my @required_args = qw(url);
   foreach my $arg ( @required_args ) {
      die "I need a $arg arugment" unless $args{$arg};
   }
   my ($url) = @args{@required_args};

   # Optional args
   my ($instances, $ua, $vc) = @args{qw(instances ua VersionCheck)};

   $ua ||= HTTPMicro->new( timeout => 2 );
   $vc ||= VersionCheck->new();

   # GET http://upgrade.percona.com, the server will return
   # a plaintext list of items/programs it wants the tool
   # to get, one item per line with the format ITEM;TYPE[;VARS]
   # ITEM is the pretty name of the item/program; TYPE is
   # the type of ITEM that helps the tool determine how to
   # get the item's version; and VARS is optional for certain
   # items/types that need extra hints.
   my $response = $ua->request('GET', $url);
   PTDEBUG && _d('Server response:', Dumper($response));
   die "No response from GET $url"
      if !$response;
   die "GET $url returned HTTP status $response->{status}; expected 200"
      if $response->{status} != 200;
   die "GET $url did not return any programs to check"
      if !$response->{content};

   # Parse the plaintext server response into a hashref keyed on
   # the items like:
   #    "MySQL" => {
   #      item => "MySQL",
   #      type => "mysql_variables",
   #      vars => ["version", "version_comment"],
   #    }
   my $items = $vc->parse_server_response(
      response => $response->{content}
   );
   die "Failed to parse server requested programs: $response->{content}"
      if !scalar keys %$items;
      
   # Get the versions for those items in another hashref also keyed on
   # the items like:
   #    "MySQL" => "MySQL Community Server 5.1.49-log",
   my $versions = $vc->get_versions(
      items     => $items,
      instances => $instances,
   );
   die "Failed to get any program versions; should have at least gotten Perl"
      if !scalar keys %$versions;

   # Join the items and whatever versions are available and re-encode
   # them in same simple plaintext item-per-line protocol, and send
   # it back to Percona.
   my $client_content = encode_client_response(
      items      => $items,
      versions   => $versions,
      general_id => md5_hex( hostname() ),
   );

   my $client_response = {
      headers => { "X-Percona-Toolkit-Tool" => File::Basename::basename($0) },
      content => $client_content,
   };
   PTDEBUG && _d('Client response:', Dumper($client_response));

   $response = $ua->request('POST', $url, $client_response);
   PTDEBUG && _d('Server suggestions:', Dumper($response));
   die "No response from POST $url $client_response"
      if !$response;
   die "POST $url returned HTTP status $response->{status}; expected 200"
      if $response->{status} != 200;

   # If the server does not have any suggestions,
   # there will not be any content.
   return unless $response->{content};

   # If the server has suggestions for items, it sends them back in
   # the same format: ITEM:TYPE:SUGGESTION\n.  ITEM:TYPE is mostly for
   # debugging; the tool just repports the suggestions.
   $items = $vc->parse_server_response(
      response   => $response->{content},
      split_vars => 0,
   );
   die "Failed to parse server suggestions: $response->{content}"
      if !scalar keys %$items;
   my @suggestions = map { $_->{vars} }
                     sort { $a->{item} cmp $b->{item} }
                     values %$items;

   return \@suggestions;
}

sub time_to_check {
   my ($file, $instance_ids) = @_;
   die "I need a file argument" unless $file;

   # If there's no time limit file, then create it and check everything.
   if ( !-f $file ) {
      PTDEBUG && _d('Creating', $file);
      _touch($file);
      return 1;
   }

   my $time = int(time());  # current time

   # If we have MySQL instances, check only the ones that haven't been
   # seen/checked before or were check > 24 hours ago.
   if ( $instance_ids && @$instance_ids ) {
      return _time_to_check_by_instances($file, $instance_ids, $time);
   }

   # No MySQL instances (happens with tools like pt-diskstats), so just
   # check the file's mtime and check if it was updated > 24 hours ago.
   my $mtime  = (stat $file)[9];
   if ( !defined $mtime ) {
      PTDEBUG && _d('Error getting modified time of', $file);
      return 0;
   }
   PTDEBUG && _d('time=', $time, 'mtime=', $mtime);
   if ( ($time - $mtime) > $check_time_limit ) {
      _touch($file);
      return 1;
   }

   # File was updated less than a day ago; don't check yet.
   return 0;
}

sub _time_to_check_by_instances {
   my ($file, $instance_ids, $time) = @_;

   # The time limit file contains "ID,time" lines for each MySQL instance
   # that the last tool connected to.  The last tool may have seen fewer
   # or more MySQL instances than the current tool, but we'll read them
   # all and check only the MySQL instances for the current tool.
   chomp(my $file_contents = Percona::Toolkit::slurp_file($file));
   my %cached_instances = $file_contents =~ /^([^,]+),(.+)$/mg;

   # Check the MySQL instances that have either 1) never been checked
   # (or seen) before, or 2) were check > 24 hours ago.
   my @instances_to_check = grep {
      my $update;
      if ( my $mtime = $cached_instances{$_} ) {
         $update = ($time - $mtime) > $check_time_limit;
      }

      if ( !$cached_instances{$_} || $update ) {
         $cached_instances{$_} = $time;
         $update = 1;
      }

      $update
   } @$instance_ids;

   # Overwrite the time limit file with the check times for instances
   # we're going to check or with the original check time for instances
   # that we're still waiting on.
   open my $fh, ">", $file
      or die "Cannot open $file for writing: $OS_ERROR";
   while ( my ($k,$v) = each %cached_instances ) {
      print { $fh } "$k,$v\n";
   }
   close $fh or die "Cannot close $file: $OS_ERROR";

   return @instances_to_check ? \@instances_to_check : 0;
}

sub _touch {
   my ($file) = @_;
   sysopen my $fh, $file, O_WRONLY|O_CREAT|O_NONBLOCK
      or die "Cannot create $file : $!";
   close $fh or die "Cannot close $file : $!";
   utime(undef, undef, $file);
}

sub _generate_identifier {
   my $instance = shift;
   my $dbh      = $instance->{dbh};
   my $dsn      = $instance->{dsn};

   my $sql  = q{SELECT MD5(CONCAT(@@hostname, @@port))};
   my ($id) = eval { $dbh->selectrow_array($sql) };
   if ( $EVAL_ERROR ) { # assume that it's MySQL 4.x
      $id = md5_hex( ($dsn->{h} || 'localhost'), ($dsn->{P} || 3306) );
   }

   return $id;
}

sub encode_client_response {
   my (%args) = @_;
   my @required_args = qw(items versions general_id);
   foreach my $arg ( @required_args ) {
      die "I need a $arg arugment" unless $args{$arg};
   }
   my ($items, $versions, $general_id) = @args{@required_args};

   # There may not be a version for each item.  For example, the server
   # may have requested the "MySQL" (version) item, but if the tool
   # didn't connect to MySQL, there won't be a $versions->{MySQL}.
   # That's ok; just use what we've got.
   # NOTE: the sort is only need to make testing deterministic.
   my @lines;
   foreach my $item ( sort keys %$items ) {
      next unless exists $versions->{$item};
      if ( ref($versions->{$item}) eq 'HASH' ) {
         my $mysql_versions = $versions->{$item};
         for my $id ( keys %$mysql_versions ) {
            push @lines, join(';', $id, $item, $mysql_versions->{$id});
         }
      }
      else {
         push @lines, join(';', $general_id, $item, $versions->{$item});
      }
   }

   my $client_response = join("\n", @lines) . "\n";
   PTDEBUG && _d('Client response:', $client_response);
   return $client_response;
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
# End Pingback package
# ###########################################################################

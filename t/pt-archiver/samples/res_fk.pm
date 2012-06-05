# This program is copyright 2009 Percona Inc.
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

package res_fk;

# This mk-archiver plugin demonstrates how to archive a table which several
# other tables reference directly and indirectly with foreign keys.  The
# tables are provided in samples/res_fk.sql.  The picutre is:
#
#   comp <---- user
#   ^          |
#   |          /
#   prod <---+
#   ^
#   |
#   prod_details
#
# prod_details references prod.  user references both prod and comp.  comp is
# the table we want to archive.  Therefore, before we can remove rows from
# comp, we must remove rows in user, prod_details then prod, else we'll
# violate a foreign key constraint:
#
#   mysql> DELETE FROM comp WHERE id=2;
#   ERROR 1451 (23000): Cannot delete or update a parent row: a foreign key
#   constraint fails (`test/prod`, CONSTRAINT `prod_comp_id` FOREIGN KEY
#   (`comp_id`) REFERENCES `comp` (`id`) ...
#
# If we were just deleteing the archived rows, things would be simple: just
# delete rows in the child tables then delete the row in the parent table,
# comp.  Instead, we'll do something slightly more complex: we'll archive
# the rows into another database with the same foreign key dependencies.
# Thus, we'll need to do special work in before_delete().

use strict;
use English qw(-no_match_vars);
use constant PTDEBUG  => $ENV{PTDEBUG};
use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

sub new {
   my ( $class, %args ) = @_;
   my $dbh = $args{dbh};
   my $src_db = "`$args{db}`";
   my $dst_db = '`test_archived`'; 

   # Prepare statements for user table.
   my $sql = "INSERT INTO $dst_db.`user` "
        . "SELECT * FROM $src_db.`user` "
        . 'WHERE comp_id=?';
   PTDEBUG && _d($sql);
   my $archive_users_sth = $dbh->prepare($sql);

   $sql = "DELETE FROM $src_db.`user` WHERE comp_id=?";
   PTDEBUG && _d($sql);
   my $delete_users_sth = $dbh->prepare($sql);

   # Prepare statements for prod table.
   $sql = "INSERT INTO $dst_db.`prod` "
        . "SELECT * FROM $src_db.`prod` "
        . 'WHERE comp_id=?';
   PTDEBUG && _d($sql);
   my $archive_prods_sth = $dbh->prepare($sql);

   $sql = "SELECT DISTINCT `id` FROM $src_db.`prod` WHERE comp_id=?";
   PTDEBUG && _d($sql);
   my $get_prods_sth = $dbh->prepare($sql);

   $sql = "DELETE FROM $src_db.`prod` WHERE comp_id=?";
   PTDEBUG && _d($sql);
   my $delete_prods_sth = $dbh->prepare($sql);

   my $self = {
      dbh               => $args{dbh},
      src_db            => $src_db,
      dst_db            => $dst_db,
      archive_users_sth => $archive_users_sth,
      delete_users_sth  => $delete_users_sth,
      archive_prods_sth => $archive_prods_sth,
      get_prods_sth     => $get_prods_sth,
      delete_prods_sth  => $delete_prods_sth,
   };

   return bless $self, $class;
}

sub before_begin {
   my ( $self, %args ) = @_;
   return;
}

sub is_archivable {
   my ( $self, %args ) = @_;
   # Use --where to select the rows you want and/or do special checks here.
   return 1;  # Archive the row.
}

# before_delete() is called after the row is inserted via the --dest dbh.
# However, we normally cannot see the inserted comp row because these are
# InnoDB tables and we're using transactions and the transactions are committed
# after the whole insert and delete operation is completed, not to mention
# that the comp row is inserted via the --dest dbh so it's visible in that
# connection's transaction before commit but not in our connection, the
# --src dbh.  There's a few ways around this.  We could use --txn-size 0
# to disable transactions, or use --skip-foreign-key-checks, or use this
# plugin with the --src dbh.  This last option would be ideal but it's not
# possible because only before_insert() is available to a --src plugin;
# we would need "after_insert()" which does not exist.  before_delete() is
# not called for the --src plugin either, else that would work since
# before_delete() is called after before_insert().  Using
# --skip-foreign-key-checks works, too, but to be safe we should not do this.
# So the solution is to use --txn-size 0.  This enables autocommit so the
# INSERT into the dest comp is visible to us.  Then we can archive the other
# tables with INSERT SELECT ($archive_*_sth).
sub before_delete {
   my ( $self, %args ) = @_;
   PTDEBUG && _d('before delete');
   my $dbh     = $self->{dbh};
   my $src_db  = $self->{src_db};
   my $dst_db  = $self->{dst_db};
   my $comp_id = $args{row}->[0];  # id is first column
   my $sql;
   PTDEBUG && _d('row:', Dumper($args{row}));

   # Archive rows from prod then user, in that order because
   # user referenes prod.
   $self->{archive_prods_sth}->execute($comp_id);
   $self->{archive_users_sth}->execute($comp_id);

   # Archiving the prod details requires a little extra work
   # because prod_details only references prod and each comp
   # may have multiple prod.  So we need to get all the prod
   # details for all the comp's prods.
   $self->{get_prods_sth}->execute($comp_id);
   my $prod_ids     = $self->{get_prods_sth}->fetchall_arrayref();
   my $all_prod_ids = join(',', map { $_->[0]; } @$prod_ids);
   PTDEBUG && _d('prod ids:', $all_prod_ids);
   my $sql = "INSERT INTO $dst_db.`prod_details` "
           . "SELECT * FROM $src_db.`prod_details` "
           . "WHERE prod_id IN ($all_prod_ids)";
   PTDEBUG && _d($sql);
   $dbh->do($sql);

   # Now we can delete the rows from user, prod_details then prod
   # on the source.  This allows mk-archiver to delete the comp row.
   $self->{delete_users_sth}->execute($comp_id);
   $sql = "DELETE FROM $src_db.`prod_details` "
        . "WHERE prod_id IN ($all_prod_ids)";
   PTDEBUG && _d($sql);
   $dbh->do($sql);
   $self->{delete_prods_sth}->execute($comp_id);

   return;
}

sub after_finish {
   my ( $self ) = @_;
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

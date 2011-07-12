#!/usr/bin/perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More tests => 7;

use Schema;
use SchemaIterator;
use ForeignKeyIterator;
use FileIterator;
use Quoter;
use TableParser;
use DSNParser;
use OptionParser;
use PerconaTest;

use constant MKDEBUG => $ENV{MKDEBUG} || 0;

use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

my $q  = new Quoter();
my $tp = new TableParser(Quoter => $q);
my $fi = new FileIterator();
my $o  = new OptionParser(description => 'SchemaIterator');
$o->get_specs("$trunk/bin/pt-table-checksum");

my $in  = "$trunk/t/lib/samples/ForeignKeyIterator/";
my $out = "t/lib/samples/ForeignKeyIterator/";

sub test_fki {
   my ( %args ) = @_;
   my @required_args = qw(files db tbl test_name result);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless defined $args{$arg};
   }

   my $fki = $args{fki};
   if ( !$fki ) {
      @ARGV = $args{filters} ? @{$args{filters}} : ();
      $o->get_opts();

      my $file_itr = $fi->get_file_itr(@{$args{files}});
      my $schema = new Schema();
      my $si    = new SchemaIterator(
         file_itr     => $file_itr,
         OptionParser => $o,
         Quoter       => $q,
         TableParser  => $tp,
         keep_ddl     => 1,
         Schema       => $schema,
      );

      $fki = new ForeignKeyIterator(
         db             => $args{db},
         tbl            => $args{tbl},
         reverse        => $args{reverse},
         SchemaIterator => $si,
         Quoter         => $q,
         TableParser    => $tp,
         Schema         => $schema,
      );
   }

   my @got_objs;
   while ( my $obj = $fki->next_schema_object() ) {
      my %got = (
         db  => $obj->{db},
         tbl => $obj->{tbl},
      );
      $got{fk_struct} = $obj->{fk_struct} if $args{fk_struct};
      push @got_objs, \%got;
   }

   is_deeply(
      \@got_objs,
      $args{result},
      $args{test_name},
   ) or print Dumper(\@got_objs);

   if ( $args{stop} ) {
      die "Stopped after test $args{test_name}";
   }

   return $fki;
}

test_fki(
   test_name => 'Iterate from address (fktbls001.sql)',
   files     => ["$in/fktbls001.sql"],
   db        => 'test',
   tbl       => 'address',
   result    => [
      {
         db  => 'test',
         tbl => 'address',
      },
      {
         db  => 'test',
         tbl => 'city',
      },
      {
         db  => 'test',
         tbl => 'country',
      },
   ],
);

test_fki(
   test_name => 'Iterate from data (fktbls002.sql)',
   files     => ["$in/fktbls002.sql"],
   db        => 'test',
   tbl       => 'data',
   fk_struct => 1,
   result    => [
      {
         db        => 'test',
         tbl       => 'data',
         fk_struct => {
            data_ibfk_1 => {
               name     => 'data_ibfk_1',
               colnames => '`data_report`',
               cols     => [ 'data_report' ],
               parent_tbl      => {db=>'test', tbl=>'data_report'},
               parent_tblname  => '`test`.`data_report`',
               parent_cols     => [ 'id' ],
               parent_colnames => '`id`',
               ddl => 'CONSTRAINT `data_ibfk_1` FOREIGN KEY (`data_report`) REFERENCES `data_report` (`id`)',
            },
            data_ibfk_2 => {
               name     => 'data_ibfk_2',
               colnames => '`entity`',
               cols     => [ 'entity' ],
               parent_tbl      => {db=>'test', tbl=>'entity'},
               parent_tblname  => '`test`.`entity`',
               parent_cols     => [ 'id' ],
               parent_colnames => '`id`',
               ddl => 'CONSTRAINT `data_ibfk_2` FOREIGN KEY (`entity`) REFERENCES `entity` (`id`)',
            },
         },
      },
      {
         db        => 'test',
         tbl       => 'entity',
         fk_struct => undef,
      },
      {
         db        => 'test',
         tbl       => 'data_report',
         fk_struct => undef,
      },
   ],
);

# There is a circular reference between store and staff, but the
# code should handle it. See http://dev.mysql.com/doc/sakila/en/sakila.html
# for the entire sakila db table structure.
test_fki(
   test_name => 'Iterate from sakila.customer',
   files     => ["$trunk/t/lib/samples/mysqldump-no-data/all-dbs.txt"],
   db        => 'sakila',
   tbl       => 'customer',
   result    => [
      { db  => 'sakila', tbl => 'customer' },
      { db  => 'sakila', tbl => 'store'    },
      { db  => 'sakila', tbl => 'staff'    },
      { db  => 'sakila', tbl => 'address'  },
      { db  => 'sakila', tbl => 'city'     },
      { db  => 'sakila', tbl => 'country'  },
   ],
);

test_fki(
   test_name => 'Iterate from sakila.customer reversed',
   files     => ["$trunk/t/lib/samples/mysqldump-no-data/all-dbs.txt"],
   db        => 'sakila',
   tbl       => 'customer',
   reverse   => 1,
   result    => [
      { db  => 'sakila', tbl => 'country'  },
      { db  => 'sakila', tbl => 'city'     },
      { db  => 'sakila', tbl => 'address'  },
      { db  => 'sakila', tbl => 'staff'    },
      { db  => 'sakila', tbl => 'store'    },
      { db  => 'sakila', tbl => 'customer' },
   ],
);


# ############################################################################
# Can we reset and re-iterate?
# ############################################################################
my $fki1 = test_fki(
   test_name => 'Iteration 1',
   files     => ["$in/fktbls001.sql"],
   db        => 'test',
   tbl       => 'address',
   result    => [
      {
         db  => 'test',
         tbl => 'address',
      },
      {
         db  => 'test',
         tbl => 'city',
      },
      {
         db  => 'test',
         tbl => 'country',
      },
   ],
);

$fki1->reset();

my $fki2 = test_fki(
   test_name => 'Iteration 2',
   files     => '',  # hack to satisfy required args,
   db        => '',  # these also insure that the given
   tbl       => '',  # fki is reused...
   fki       => $fki1,
   result    => [
      {
         db  => 'test',
         tbl => 'address',
      },
      {
         db  => 'test',
         tbl => 'city',
      },
      {
         db  => 'test',
         tbl => 'country',
      },
   ],
);

is(
   $fki1,
   $fki2,
   'Reset and reused ForeignKeyIterator'
);

# #############################################################################
# Done.
# #############################################################################
exit;

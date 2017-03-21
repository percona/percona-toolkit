#!/usr/bin/perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More;

use OptionParser;
use DSNParser;
use PerconaTest;

use Test::More tests => 161;
my $o  = new OptionParser(
   description  => 'OptionParser.t parses command line options.',
   usage        => "$PROGRAM_NAME <options>",
);

isa_ok($o, 'OptionParser');

my @opt_specs;
my %opts;
my $output;

# Prevent print_usage() from breaking lines in the first paragraph
# at 80 chars width.  This paragraph contains $PROGRAM_NAME and that
# becomes too long when this test is ran from trunk, causing a break.
# To make this test path-independent, we don't break lines.  This only
# affects testing.
$ENV{DONT_BREAK_LINES} = 1;

# Some tests need a DSNParser but we don't provide a POD with a
# DSN OPTIONS section that would cause the OptionParser to create
# a DSNParser automatically.  So we create the DSNParser manually
# and hack it into the OptionParser.
my $dsn_opts = [
   {
      key => 'A',
      desc => 'Default character set',
      dsn  => 'charset',
      copy => 1,
   },
   {
      key => 'D',
      desc => 'Database to use',
      dsn  => 'database',
      copy => 1,
   },
   {
      key => 'F',
      desc => 'Only read default options from the given file',
      dsn  => 'mysql_read_default_file',
      copy => 1,
   },
   {
      key => 'h',
      desc => 'Connect to host',
      dsn  => 'host',
      copy => 1,
   },
   {
      key => 'p',
      desc => 'Password to use when connecting',
      dsn  => 'password',
      copy => 1,
   },
   {
      key => 'P',
      desc => 'Port number to use for connection',
      dsn  => 'port',
      copy => 1,
   },
   {
      key => 'S',
      desc => 'Socket file to use for connection',
      dsn  => 'mysql_socket',
      copy => 1,
   },
   {
      key => 'u',
      desc => 'User for login if not current user',
      dsn  => 'user',
      copy => 1,
   },
];
my $dp = new DSNParser(opts => $dsn_opts);

# #############################################################################
# Test basic usage.
# #############################################################################

# Quick test of standard interface.
$o->get_specs("$trunk/t/lib/samples/pod/pod_sample_01.txt");
%opts = $o->opts();
ok(
   exists $opts{help},
   'get_specs() basic interface'
);

# More exhaustive test of how the standard interface works internally.
$o  = new OptionParser(
   description => 'OptionParser.t parses command line options.',
   usage       => "$PROGRAM_NAME <options>",
);
ok(!$o->has('time'), 'There is no --time yet');
@opt_specs = $o->_pod_to_specs("$trunk/t/lib/samples/pod/pod_sample_01.txt");

# hacky workaround for the next test:
# since now opt_specs includes the attributes hash, but it's a pain to
# check for all of those, we simply remove it.
@opt_specs = map {delete $_->{'attributes'}; $_ } @opt_specs;

is_deeply(
   \@opt_specs,
   [
   { spec=>'database|D=s', group=>'default', desc=>'database string',         },
   { spec=>'port|p=i',     group=>'default', desc=>'port (default 3306)',     },
   { spec=>'price=f',    group=>'default', desc=>'price float (default 1.23)' },
   { spec=>'hash-req=H', group=>'default', desc=>'hash that requires a value' },
   { spec=>'hash-opt=h', group=>'default', desc=>'hash with an optional value'},
   { spec=>'array-req=A',group=>'default', desc=>'array that requires a value'},
   { spec=>'array-opt=a',group=>'default',desc=>'array with an optional value'},
   { spec=>'host=d',       group=>'default', desc=>'host DSN'           },
   { spec=>'chunk-size=z', group=>'default', desc=>'chunk size'         },
   { spec=>'time=m',       group=>'default', desc=>'time'               },
   { spec=>'help+',        group=>'default', desc=>'help cumulative'    },
   { spec=>'other!',       group=>'default', desc=>'other negatable'    },
   ],
   'Convert POD OPTIONS to opt specs (pod_sample_01.txt)',
);

$o->_parse_specs(@opt_specs);
ok($o->has('time'), 'There is a --time now');
%opts = $o->opts();

is_deeply(
   \%opts,
   {
      'database'   => {
         spec           => 'database|D=s',
         desc           => 'database string',
         group          => 'default',
         long           => 'database',
         short          => 'D',
         is_cumulative  => 0,
         is_negatable   => 0,
         is_required    => 0,
         is_repeatable  => 0,
         type           => 's',
         got            => 0,
         value          => undef,
         attributes     => {},
      },
      'port'       => {
         spec           => 'port|p=i',
         desc           => 'port (default 3306)',
         group          => 'default',
         long           => 'port',
         short          => 'p',
         is_cumulative  => 0,
         is_negatable   => 0,
         is_required    => 0,
         is_repeatable  => 0,
         type           => 'i',
         got            => 0,
         value          => undef,
         attributes     => {},
      },
      'price'      => {
         spec           => 'price=f',
         desc           => 'price float (default 1.23)',
         group          => 'default',
         long           => 'price',
         short          => undef,
         is_cumulative  => 0,
         is_negatable   => 0,
         is_required    => 0,
         is_repeatable  => 0,
         type           => 'f',
         got            => 0,
         value          => undef,
         attributes     => {},
      },
      'hash-req'   => {
         spec           => 'hash-req=s',
         desc           => 'hash that requires a value',
         group          => 'default',
         long           => 'hash-req',
         short          => undef,
         is_cumulative  => 0,
         is_negatable   => 0,
         is_required    => 0,
         is_repeatable  => 0,
         type           => 'H',
         got            => 0,
         value          => undef,
         attributes     => {},
      },
      'hash-opt'   => {
         spec           => 'hash-opt=s',
         desc           => 'hash with an optional value',
         group          => 'default',
         long           => 'hash-opt',
         short          => undef,
         is_cumulative  => 0,
         is_negatable   => 0,
         is_required    => 0,
         is_repeatable  => 0,
         type           => 'h',
         got            => 0,
         value          => undef,
         attributes     => {},
      },
      'array-req'  => {
         spec           => 'array-req=s',
         desc           => 'array that requires a value',
         group          => 'default',
         long           => 'array-req',
         short          => undef,
         is_cumulative  => 0,
         is_negatable   => 0,
         is_required    => 0,
         is_repeatable  => 0,
         type           => 'A',
         got            => 0,
         value          => undef,
         attributes     => {},
      },
      'array-opt'  => {
         spec           => 'array-opt=s',
         desc           => 'array with an optional value',
         group          => 'default',
         long           => 'array-opt',
         short          => undef,
         is_cumulative  => 0,
         is_negatable   => 0,
         is_required    => 0,
         is_repeatable  => 0,
         type           => 'a',
         got            => 0,
         value          => undef,
         attributes     => {},
      },
      'host'       => {
         spec           => 'host=s',
         desc           => 'host DSN',
         group          => 'default',
         long           => 'host',
         short          => undef,
         is_cumulative  => 0,
         is_negatable   => 0,
         is_required    => 0,
         is_repeatable  => 0,
         type           => 'd',
         got            => 0,
         value          => undef,
         attributes     => {},
      },
      'chunk-size' => {
         spec           => 'chunk-size=s',
         desc           => 'chunk size',
         group          => 'default',
         long           => 'chunk-size',
         short          => undef,
         is_cumulative  => 0,
         is_negatable   => 0,
         is_required    => 0,
         is_repeatable  => 0,
         type           => 'z',
         got            => 0,
         value          => undef,
         attributes     => {},
      },
      'time'       => {
         spec           => 'time=s',
         desc           => 'time',
         group          => 'default',
         long           => 'time',
         short          => undef,
         is_cumulative  => 0,
         is_negatable   => 0,
         is_required    => 0,
         is_repeatable  => 0,
         type           => 'm',
         got            => 0,
         value          => undef,
         attributes     => {},
      },
      'help'       => {
         spec           => 'help+',
         desc           => 'help cumulative',
         group          => 'default',
         long           => 'help',
         short          => undef,
         is_cumulative  => 1,
         is_negatable   => 0,
         is_required    => 0,
         is_repeatable  => 0,
         type           => undef,
         got            => 0,
         value          => undef,
         attributes     => {},
      },
      'other'      => {
         spec           => 'other!',
         desc           => 'other negatable',
         group          => 'default',
         long           => 'other',
         short          => undef,
         is_cumulative  => 0,
         is_negatable   => 1,
         is_required    => 0,
         is_repeatable  => 0,
         type           => undef,
         got            => 0,
         value          => undef,
         attributes     => {},
      }
   },
   'Parse opt specs'
);

%opts = $o->short_opts();
is_deeply(
   \%opts,
   {
      'D' => 'database',
      'p' => 'port',
   },
   'Short opts => log opts'
);

# get() single option
is(
   $o->get('database'),
   undef,
   'Get valueless long opt'
);
is(
   $o->get('p'),
   undef,
   'Get valuless short opt'
);
eval { $o->get('foo'); };
like(
   $EVAL_ERROR,
   qr/Option foo does not exist/,
   'Die trying to get() nonexistent long opt'
);
eval { $o->get('x'); };
like(
   $EVAL_ERROR,
   qr/Option x does not exist/,
   'Die trying to get() nonexistent short opt'
);

# set()
$o->set('database', 'foodb');
is(
   $o->get('database'),
   'foodb',
   'Set long opt'
);
$o->set('p', 12345);
is(
   $o->get('p'),
   12345,
   'Set short opt'
);
eval { $o->set('foo', 123); };
like(
   $EVAL_ERROR,
   qr/Option foo does not exist/,
   'Die trying to set() nonexistent long opt'
);
eval { $o->set('x', 123); };
like(
   $EVAL_ERROR,
   qr/Option x does not exist/,
   'Die trying to set() nonexistent short opt'
);

# got()
@ARGV = qw(--port 12345);
$o->get_opts();
is(
   $o->got('port'),
   1,
   'Got long opt'
);
is(
   $o->got('p'),
   1,
   'Got short opt'
);
is(
   $o->got('database'),
   0,
   'Did not "got" long opt'
);
is(
   $o->got('D'),
   0,
   'Did not "got" short opt'
);

eval { $o->got('foo'); };
like(
   $EVAL_ERROR,
   qr/Option foo does not exist/,
   'Die trying to got() nonexistent long opt',
);
eval { $o->got('x'); };
like(
   $EVAL_ERROR,
   qr/Option x does not exist/,
   'Die trying to got() nonexistent short opt',
);

@ARGV = qw(--bar);
eval {
   local *STDERR;
   open STDERR, '>', '/dev/null';
   $o->get_opts();
   $o->get('bar');
};
like(
   $EVAL_ERROR,
   qr/Option bar does not exist/,
   'Ignore nonexistent opt given on cmd line'
);

@ARGV = qw(--port 12345);
$o->get_opts();
is_deeply(
   $o->errors(),
   [],
   'get_opts() resets errors'
);

ok(
   $o->has('D'),
   'Has short opt' 
);
ok(
   !$o->has('X'),
   'Does not "has" nonexistent short opt'
);

# #############################################################################
# Test hostile, broken usage.
# #############################################################################
eval { $o->_pod_to_specs("$trunk/t/lib/samples/pod/pod_sample_02.txt"); };
like(
   $EVAL_ERROR,
   qr/POD has no OPTIONS section/,
   'Dies on POD without an OPTIONS section'
);

eval { $o->_pod_to_specs("$trunk/t/lib/samples/pod/pod_sample_03.txt"); };
like(
   $EVAL_ERROR,
   qr/No valid specs in OPTIONS/,
   'Dies on POD with an OPTIONS section but no option items'
);

eval { $o->_pod_to_specs("$trunk/t/lib/samples/pod/pod_sample_04.txt"); };
like(
   $EVAL_ERROR,
   qr/No description after option spec foo/,
   'Dies on option with no description'
);

# TODO: more hostile tests: duplicate opts, can't parse long opt from spec,
# unrecognized rules, ...

# #############################################################################
# Test option defaults.
# #############################################################################
$o = new OptionParser(
   description => 'OptionParser.t parses command line options.',
   usage       => "$PROGRAM_NAME [OPTIONS]",
);
# These are dog opt specs. They're used by other tests below.
$o->_parse_specs(
   {
      spec => 'defaultset!',
      desc => 'alignment test with a very long thing '
            . 'that is longer than 80 characters wide '
            . 'and must be wrapped'
   },
   { spec => 'defaults-file|F=s', desc => 'alignment test'  },
   { spec => 'dog|D=s',           desc => 'Dogs are fun'    },
   { spec => 'foo!',              desc => 'Foo'             },
   { spec => 'love|l+',           desc => 'And peace'       },
);

is_deeply(
   $o->get_defaults(),
   {},
   'No default defaults',
);

$o->set_defaults(foo => 1);
is_deeply(
   $o->get_defaults(),
   {
      foo => 1,
   },
   'set_defaults() with values'
);

$o->set_defaults();
is_deeply(
   $o->get_defaults(),
   {},
   'set_defaults() without values unsets defaults'
);

# We've already tested opt spec parsing,
# but we do it again for thoroughness.
%opts = $o->opts();
is_deeply(
   \%opts,
   {
      'foo'           => {
         spec           => 'foo!',
         desc           => 'Foo',
         group          => 'default',
         long           => 'foo',
         short          => undef,
         is_cumulative  => 0,
         is_negatable   => 1,
         is_required    => 0,
         is_repeatable  => 0,
         type           => undef,
         got            => 0,
         value          => undef,
         attributes     => {},
      },
      'defaultset'    => {
         spec           => 'defaultset!',
         desc           => 'alignment test with a very long thing '
                         . 'that is longer than 80 characters wide '
                         . 'and must be wrapped',
         group          => 'default',
         long           => 'defaultset',
         short          => undef,
         is_cumulative  => 0,
         is_negatable   => 1,
         is_required    => 0,
         is_repeatable  => 0,
         type           => undef,
         got            => 0,
         value          => undef,
         attributes     => {},
      },
      'defaults-file' => {
         spec           => 'defaults-file|F=s',
         desc           => 'alignment test',
         group          => 'default',
         long           => 'defaults-file',
         short          => 'F',
         is_cumulative  => 0,
         is_negatable   => 0,
         is_required    => 0,
         is_repeatable  => 0,
         type           => 's',
         got            => 0,
         value          => undef,
         attributes     => {},
      },
      'dog'           => {
         spec           => 'dog|D=s',
         desc           => 'Dogs are fun',
         group          => 'default',
         long           => 'dog',
         short          => 'D',
         is_cumulative  => 0,
         is_negatable   => 0,
         is_required    => 0,
         is_repeatable  => 0,
         type           => 's',
         got            => 0,
         value          => undef,
         attributes     => {},
      },
      'love'          => {
         spec           => 'love|l+',
         desc           => 'And peace',
         group          => 'default',
         long           => 'love',
         short          => 'l',
         is_cumulative  => 1,
         is_negatable   => 0,
         is_required    => 0,
         is_repeatable  => 0,
         type           => undef,
         got            => 0,
         value          => undef,
         attributes     => {},
      },
   },
   'Parse dog specs'
);

$o->set_defaults('dog' => 'fido');

@ARGV = ();
$o->get_opts();
is(
   $o->get('dog'),
   'fido',
   'Opt gets default value'
);
is(
   $o->got('dog'),
   0,
   'Did not "got" opt with default value'
);

@ARGV = qw(--dog rover);
$o->get_opts();
is(
   $o->get('dog'),
   'rover',
   'Value given on cmd line overrides default value'
);

eval { $o->set_defaults('bone' => 1) };
like(
   $EVAL_ERROR,
   qr/Cannot set default for nonexistent option bone/,
   'Cannot set default for nonexistent option'
);

# #############################################################################
# Test option attributes negatable and cumulative.
# #############################################################################

# These tests use the dog opt specs from above.

@ARGV = qw(--nofoo);
$o->get_opts();
is(
   $o->get('foo'),
   0,
   'Can negate negatable opt like --nofoo'
);

@ARGV = qw(--no-foo);
$o->get_opts();
is(
   $o->get('foo'),
   0,
   'Can negate negatable opt like --no-foo'
);

@ARGV = qw(--nodog);
{
   local *STDERR;
   open STDERR, '>', '/dev/null';
   $o->get_opts();
}
is_deeply(
   $o->get('dog'),
   undef,
   'Cannot negate non-negatable opt'
);
is_deeply(
   $o->errors(),
   ['Error parsing options'],
   'Trying to negate non-negatable opt sets an error'
);

@ARGV = ();
$o->get_opts();
is(
   $o->get('love'),
   0,
   'Cumulative defaults to 0 when not given'
);

@ARGV = qw(--love -l -l);
$o->get_opts();
is(
   $o->get('love'),
   3,
   'Cumulative opt val increases (--love -l -l)'
);
is(
   $o->got('love'),
   1,
   "got('love') when given multiple times short and long"
);

@ARGV = qw(--love);
$o->get_opts();
is(
   $o->got('love'),
   1,
   "got('love') long once"
);

@ARGV = qw(-l);
$o->get_opts();
is(
   $o->got('l'),
   1,
   "got('l') short once"
);

# #############################################################################
# Test usage output.
# #############################################################################

# The following one test uses the dog opt specs from above.

my $prog_name = $PROGRAM_NAME;
$prog_name    =~ s/([\.\/\\])/\\$1/g;

my $home_esc = $ENV{HOME};
$home_esc   =~ s/([\.\/\\])/\\$1/g;

my $trunk_esc = $trunk;
$trunk_esc    =~ s/([\.\/\\])/\\$1/g;

sub check_usage {
   my ( $o, $file ) = @_;
   die "I need an OptionParser object" unless $o;
   die "I need a file name" unless $file;

   no_diff(
      $o->print_usage(),
      "t/lib/samples/OptionParser/$file",
      cmd_output => 1,
      sed        => [
         "'s/ $prog_name/ \$PROGRAM_NAME/g'",
         "'s/$trunk_esc/\$trunk/g'",
         "'s/$home_esc/\$ENV\{HOME\}/g'",
      ],
   ),
}

# Clear values from previous tests.
$o->set_defaults();
@ARGV = ();
$o->get_opts();

ok(
   check_usage($o, "help001.txt"),
   'Options aligned and custom prompt included'
);

$o = new OptionParser(
   description => 'OptionParser.t parses command line options.',
   usage       => "$PROGRAM_NAME <options>",
);
$o->_parse_specs(
   { spec => 'database|D=s',    desc => 'Specify the database for all tables' },
   { spec => 'nouniquechecks!', desc => 'Set UNIQUE_CHECKS=0 before LOAD DATA INFILE' },
);
$o->get_opts();
ok(
   check_usage($o, "help002.txt"),
   'Really long option aligns with shorts, and prompt defaults to <options>'
);

# #############################################################################
# Test _get_participants()
# #############################################################################
$o = new OptionParser(
   description => 'OptionParser.t parses command line options.',
   usage       => "$PROGRAM_NAME <options>",
);
$o->_parse_specs(
   { spec => 'foo',      desc => 'opt' },
   { spec => 'bar-bar!', desc => 'opt' },
   { spec => 'baz',      desc => 'opt' },
);
is_deeply(
   [ $o->_get_participants('L<"--foo"> disables --bar-bar and C<--baz>') ],
   [qw(foo bar-bar baz)],
   'Extract option names from a string',
);

is_deeply(
   [ $o->_get_participants('L<"--foo"> disables L<"--[no]bar-bar">.') ],
   [qw(foo bar-bar)],
   'Extract [no]-negatable option names from a string',
);
# TODO: test w/ opts that don't exist, or short opts

# #############################################################################
# Test required options.
# #############################################################################
$o = new OptionParser(
   description => 'OptionParser.t parses command line options.',
   usage       => "$PROGRAM_NAME <options>",
);
$o->_parse_specs(
   { spec => 'cat|C=s', desc => 'How to catch the cat; required' }
);

@ARGV = ();
$o->get_opts();
is_deeply(
   $o->errors(),
   ['Required option --cat must be specified'],
   'Missing required option sets an error',
);

is(
   $o->print_errors(),
"Usage: $PROGRAM_NAME <options>

Errors in command-line arguments:
  * Required option --cat must be specified

OptionParser.t parses command line options.  For more details, please use the --help option, or try 'perldoc $PROGRAM_NAME' for complete documentation.",
   'Error output includes note about missing required option'
);

@ARGV = qw(--cat net);
$o->get_opts();
is(
   $o->get('cat'),
   'net',
   'Required option OK',
);

# #############################################################################
# Test option rules.
# #############################################################################
$o = new OptionParser(
   description => 'OptionParser.t parses command line options.',
   usage       => "$PROGRAM_NAME <options>",
);
$o->_parse_specs(
   { spec => 'ignore|i',  desc => 'Use IGNORE for INSERT statements'         },
   { spec => 'replace|r', desc => 'Use REPLACE instead of INSERT statements' },
   '--ignore and --replace are mutually exclusive.',
);

$o->get_opts();
ok(
   check_usage($o, "help003.txt"),
   'Usage with rules'
);

@ARGV = qw(--replace);
$o->get_opts();
is_deeply(
   $o->errors(),
   [],
   '--replace does not trigger an error',
);

@ARGV = qw(--ignore --replace);
$o->get_opts();
is_deeply(
   $o->errors(),
   ['--ignore and --replace are mutually exclusive.'],
   'Error set when rule violated',
);

# These are used several times in the follow tests.
my @ird_specs = (
   { spec => 'ignore|i',   desc => 'Use IGNORE for INSERT statements'         },
   { spec => 'replace|r',  desc => 'Use REPLACE instead of INSERT statements' },
   { spec => 'delete|d',   desc => 'Delete'                                   },
);

$o = new OptionParser(
   description => 'OptionParser.t parses command line options.',
   usage       => "$PROGRAM_NAME <options>",
);
$o->_parse_specs(
   @ird_specs,
   '--ignore, --replace and --delete are mutually exclusive.',
);
@ARGV = qw(--ignore --replace);
$o->get_opts();
is_deeply(
   $o->errors(),
   ['--ignore, --replace and --delete are mutually exclusive.'],
   'Error set with long opt name and nice commas when rule violated',
);

$o = new OptionParser(
   description => 'OptionParser.t parses command line options.',
   usage       => "$PROGRAM_NAME <options>",
);
eval {
   $o->_parse_specs(
      @ird_specs,
     'Use one and only one of --insert, --replace, or --delete.',
   );
};
like(
   $EVAL_ERROR,
   qr/Option --insert does not exist/,
   'Die on using nonexistent option in one-and-only-one rule'
);

$o = new OptionParser(
   description  => 'OptionParser.t parses command line options.',
   usage        => "$PROGRAM_NAME <options>",
);
$o->_parse_specs(
   @ird_specs,
   'Use one and only one of --ignore, --replace, or --delete.',
);
@ARGV = qw(--ignore --replace);
$o->get_opts();
is_deeply(
   $o->errors(),
   ['--ignore, --replace and --delete are mutually exclusive.'],
   'Error set with one-and-only-one rule violated',
);

$o = new OptionParser(
   description  => 'OptionParser.t parses command line options.',
   usage        => "$PROGRAM_NAME <options>"
);
$o->_parse_specs(
   @ird_specs,
   'Use one and only one of --ignore, --replace, or --delete.',
);
@ARGV = ();
$o->get_opts();
is_deeply(
   $o->errors(),
   ['Specify at least one of --ignore, --replace or --delete'],
   'Error set with one-and-only-one when none specified',
);

$o = new OptionParser(
   description  => 'OptionParser.t parses command line options.',
   usage        => "$PROGRAM_NAME <options>"
);
$o->_parse_specs(
   @ird_specs,
   'Use at least one of --ignore, --replace, or --delete.',
);
@ARGV = ();
$o->get_opts();
is_deeply(
   $o->errors(),
   ['Specify at least one of --ignore, --replace or --delete'],
   'Error set with at-least-one when none specified',
);

$o = new OptionParser(
   description  => 'OptionParser.t parses command line options.',
   usage        => "$PROGRAM_NAME <options>"
);
$o->_parse_specs(
   @ird_specs,
   'Use at least one of --ignore, --replace, or --delete.',
);
@ARGV = qw(-ir);
$o->get_opts();
ok(
   $o->get('ignore') == 1 && $o->get('replace') == 1,
   'Multiple options OK for at-least-one',
);
use Data::Dumper;
$Data::Dumper::Indent=1;
$o = new OptionParser(
   description  => 'OptionParser.t parses command line options.',
   usage        => "$PROGRAM_NAME <options>"
);
$o->_parse_specs(
   { spec => 'foo=i', desc => 'Foo disables --bar'   },
   { spec => 'bar',   desc => 'Bar (default 1)'      },
);
@ARGV = qw(--foo 5);
$o->get_opts();
is_deeply(
   [ $o->get('foo'),  $o->get('bar') ],
   [ 5, undef ],
   '--foo disables --bar',
);
%opts = $o->opts();
is_deeply(
   $opts{'bar'},
   {
      spec          => 'bar',
      is_required   => 0,
      value         => undef,
      is_cumulative => 0,
      short         => undef,
      group         => 'default',
      got           => 0,
      is_negatable  => 0,
      is_repeatable => 0,
      desc          => 'Bar (default 1)',
      long          => 'bar',
      type          => undef,
      parsed        => 1,
      attributes    => {},
   },
   'Disabled opt is not destroyed'
);

# Option can't disable a nonexistent option.
$o = new OptionParser(
   description  => 'OptionParser.t parses command line options.',
   usage        => "$PROGRAM_NAME <options>"
);
eval {
   $o->_parse_specs(
      { spec => 'foo=i', desc => 'Foo disables --fox' },
      { spec => 'bar',   desc => 'Bar (default 1)'    },
   );
};
like(
   $EVAL_ERROR,
   qr/Option --fox does not exist/,
   'Invalid option name in disable rule',
);

# Option can't 'allowed with' a nonexistent option.
$o = new OptionParser(
   description  => 'OptionParser.t parses command line options.',
   usage        => "$PROGRAM_NAME <options>"
);
eval {
   $o->_parse_specs(
      { spec => 'foo=i', desc => 'Foo disables --bar' },
      { spec => 'bar',   desc => 'Bar (default 0)'    },
      'allowed with --foo: --fox',
   );
};
like(
   $EVAL_ERROR,
   qr/Option --fox does not exist/,
   'Invalid option name in \'allowed with\' rule',
);

# #############################################################################
# Test default values encoded in description.
# #############################################################################
$o = new OptionParser(
   description  => 'OptionParser.t parses command line options.',
   usage        => "$PROGRAM_NAME <options>"
);
# Hack DSNParser into OptionParser.  This is just for testing.
$o->{DSNParser} = $dp;

$o->_parse_specs(
   { spec => 'foo=i',   desc => 'Foo (default 5)'                 },
   { spec => 'bar',     desc => 'Bar (default)'                   },
   { spec => 'price=f', desc => 'Price (default 12345.123456)'    },
   { spec => 'size=z',  desc => 'Size (default 128M)'             },
   { spec => 'time=m',  desc => 'Time (default 24h)'              },
   { spec => 'host=d',  desc => 'Host (default h=127.1,P=12345)'  },
);
@ARGV = ();
$o->get_opts();
is(
   $o->get('foo'),
   5,
   'Default integer value encoded in description'
);
is(
   $o->get('bar'),
   1,
   'Default option enabled encoded in description'
);
is(
   $o->get('price'),
   12345.123456,
   'Default float value encoded in description'
);
is(
   $o->get('size'),
   134217728,
   'Default size value encoded in description'
);
is(
   $o->get('time'),
   86400,
   'Default time value encoded in description'
);
is_deeply(
   $o->get('host'),
   {
      S => undef,
      F => undef,
      A => undef,
      p => undef,
      u => undef,
      h => '127.1',
      D => undef,
      P => '12345'
   },
   'Default host value encoded in description'
);

is(
   $o->got('foo'),
   0,
   'Did not "got" --foo with encoded default'
);
is(
   $o->got('bar'),
   0,
   'Did not "got" --bar with encoded default'
);
is(
   $o->got('price'),
   0,
   'Did not "got" --price with encoded default'
);
is(
   $o->got('size'),
   0,
   'Did not "got" --size with encoded default'
);
is(
   $o->got('time'),
   0,
   'Did not "got" --time with encoded default'
);
is(
   $o->got('host'),
   0,
   'Did not "got" --host with encoded default'
);

# #############################################################################
# Test size option type.
# #############################################################################
$o = new OptionParser(
   description  => 'OptionParser.t parses command line options.',
   usage        => "$PROGRAM_NAME <options>"
);
$o->_parse_specs(
   { spec => 'size=z', desc => 'size' }
);

@ARGV = qw(--size 5k);
$o->get_opts();
is_deeply(
   $o->get('size'),
   1024*5,
   '5K expanded',
);

@ARGV = qw(--size -5k);
$o->get_opts();
is_deeply(
   $o->get('size'),
   -1024*5,
   '-5K expanded',
);

@ARGV = qw(--size +5k);
$o->get_opts();
is_deeply(
   $o->get('size'),
   '+' . (1024*5),
   '+5K expanded',
);

@ARGV = qw(--size 5);
$o->get_opts();
is_deeply(
   $o->get('size'),
   5,
   '5 expanded',
);

@ARGV = qw(--size 5z);
$o->get_opts();
is_deeply(
   $o->errors(),
   ['Invalid size for --size: 5z'],
   'Bad size argument sets an error',
);

# #############################################################################
# Test time option type.
# #############################################################################
$o = new OptionParser(
   description  => 'OptionParser.t parses command line options.',
   usage        => "$PROGRAM_NAME <options>"
);
$o->_parse_specs(
   { spec => 't=m', desc => 'Time'            },
   { spec => 's=m', desc => 'Time (suffix s)' },
   { spec => 'm=m', desc => 'Time (suffix m)' },
   { spec => 'h=m', desc => 'Time (suffix h)' },
   { spec => 'd=m', desc => 'Time (suffix d)' },
);

@ARGV = qw(-t 10 -s 20 -m 30 -h 40 -d 50);
$o->get_opts();
is_deeply(
   $o->get('t'),
   10,
   'Time value with default suffix decoded',
);
is_deeply(
   $o->get('s'),
   20,
   'Time value with s suffix decoded',
);
is_deeply(
   $o->get('m'),
   30*60,
   'Time value with m suffix decoded',
);
is_deeply(
   $o->get('h'),
   40*3600,
   'Time value with h suffix decoded',
);
is_deeply(
   $o->get('d'),
   50*86400,
   'Time value with d suffix decoded',
);

@ARGV = qw(-d 5m);
$o->get_opts();
is_deeply(
   $o->get('d'),
   5*60,
   'Explicit suffix overrides default suffix'
);

# Use shorter, simpler specs to test usage for time blurb.
$o = new OptionParser(
   description  => 'OptionParser.t parses command line options.',
   usage        => "$PROGRAM_NAME <options>",
);
$o->_parse_specs(
   { spec => 'foo=m', desc => 'Time' },
   { spec => 'bar=m', desc => 'Time (suffix m)' },
);
$o->get_opts();
ok(
   check_usage($o, "help004.txt"),
   'Usage for time value'
);

@ARGV = qw(--foo 5z);
$o->get_opts();
is_deeply(
   $o->errors(),
   ['Invalid time suffix for --foo'],
   'Bad time argument sets an error',
);

# #############################################################################
# Test DSN option type.
# #############################################################################
$o = new OptionParser(
   description  => 'OptionParser.t parses command line options.',
   usage        => "$PROGRAM_NAME <options>"
);
# Hack DSNParser into OptionParser.  This is just for testing.
$o->{DSNParser} = $dp;
$o->_parse_specs(
   { spec => 'foo=d', desc => 'DSN foo' },
   { spec => 'bar=d', desc => 'DSN bar' },
   'DSN values in --foo default to values in --bar if COPY is yes.',
);
$o->get_opts();
ok(
   check_usage($o, "help005.txt"),
   'DSN is integrated into help output'
);

@ARGV = ('--bar', 'D=DB,u=USER,h=localhost', '--foo', 'h=otherhost');
$o = new OptionParser(
   description  => 'OptionParser.t parses command line options.',
   usage        => "$PROGRAM_NAME <options>"
);
# Hack DSNParser into OptionParser.  This is just for testing.
$o->{DSNParser} = $dp;
$o->_parse_specs(
   { spec => 'foo=d', desc => 'DSN foo' },
   { spec => 'bar=d', desc => 'DSN bar' },
   'DSN values in --foo default to values in --bar if COPY is yes.',
);
$o->get_opts();
is_deeply(
   $o->get('bar'),
   {
      D => 'DB',
      u => 'USER',
      S => undef,
      F => undef,
      P => undef,
      h => 'localhost',
      p => undef,
      A => undef,
   },
   'DSN parsing on type=d',
);
is_deeply(
   $o->get('foo'),
   {
      D => 'DB',
      u => 'USER',
      S => undef,
      F => undef,
      P => undef,
      h => 'otherhost',
      p => undef,
      A => undef,
   },
   'DSN parsing on type=d inheriting from --bar',
);

ok(
   check_usage($o, "help006.txt"),
   'DSN stringified with inheritance into post-processed args'
);

$o = new OptionParser(
   description  => 'OptionParser.t parses command line options.',
   usage        => "$PROGRAM_NAME <options>"
);
# Hack DSNParser into OptionParser.  This is just for testing.
$o->{DSNParser} = $dp;

$o->_parse_specs(
   { spec => 'foo|f=d', desc => 'DSN foo' },
   { spec => 'bar|b=d', desc => 'DSN bar' },
   'DSN values in --foo default to values in --bar if COPY is yes.',
);
@ARGV = ('-b', 'D=DB,u=USER,h=localhost', '-f', 'h=otherhost');
$o->get_opts();
is_deeply(
   $o->get('f'),
   {
      D => 'DB',
      u => 'USER',
      S => undef,
      F => undef,
      P => undef,
      h => 'otherhost',
      p => undef,
      A => undef,
   },
   'DSN parsing on type=d inheriting from --bar with short options',
);

# #############################################################################
# Test [Hh]ash and [Aa]rray option types.
# #############################################################################
$o = new OptionParser(
   description  => 'OptionParser.t parses command line options.',
   usage        => "$PROGRAM_NAME <options>"
);
$o->_parse_specs(
   { spec => 'columns|C=H',   desc => 'cols required'       },
   { spec => 'tables|t=h',    desc => 'tables optional'     },
   { spec => 'databases|d=A', desc => 'databases required'  },
   { spec => 'books|b=a',     desc => 'books optional'      },
   { spec => 'foo=A',         desc => 'foo (default a,b,c)' },
);

@ARGV = ();
$o->get_opts();
is_deeply(
   $o->get('C'),
   {},
   'required Hash'
);
is_deeply(
   $o->get('t'),
   undef,
   'optional hash'
);
is_deeply(
   $o->get('d'),
   [],
   'required Array'
);
is_deeply(
   $o->get('b'),
   undef,
   'optional array'
);
is_deeply($o->get('foo'), [qw(a b c)], 'Array got a default');

@ARGV = ('-C', 'a,b', '-t', 'd, e', '-d', 'f,g', '-b', 'o,p' );
$o->get_opts();
%opts = (
   C => $o->get('C'),
   t => $o->get('t'),
   d => $o->get('d'),
   b => $o->get('b'),
);
is_deeply(
   \%opts,
   {
      C => { a => 1, b => 1 },
      t => { d => 1, e => 1 },
      d => [qw(f g)],
      b => [qw(o p)],
   },
   'Comma-separated lists: all processed when given',
);

ok(
   check_usage($o, "help007.txt"),
   'Lists properly expanded into usage information',
);

# #############################################################################
# Test groups.
# #############################################################################

$o = new OptionParser(
   description  => 'OptionParser.t parses command line options.',
   usage        => "$PROGRAM_NAME <options>"
);
$o->get_specs("$trunk/t/lib/samples/pod/pod_sample_05.txt");

is_deeply(
   $o->get_groups(),
   {
      'Help'       => {
         'explain-hosts' => 1,
         'help'          => 1,
         'version'       => 1,
      },
      'Filter'     => { 'databases'     => 1, },
      'Output'     => { 'tab'           => 1, },
      'Connection' => { 'defaults-file' => 1, },
      'default'    => {
         'algorithm' => 1,
         'schema'    => 1,
      }
   },
   'get_groups()'
);

@ARGV = ();
$o->get_opts();
ok(
   check_usage($o, "help008.txt"),
   'Option groupings usage',
);

@ARGV = qw(--schema --tab);
$o->get_opts();
ok(
   $o->get('schema') && $o->get('tab'),
   'Opt allowed with opt from allowed group'
);

@ARGV = qw(--schema --algorithm ACCUM);
$o->get_opts();
is_deeply(
   $o->errors(),
   ['--schema is not allowed with --algorithm'],
   'Opt is not allowed with opt from restricted group'
);

# #############################################################################
# Test clone().
# #############################################################################
$o = new OptionParser(
   description  => 'OptionParser.t parses command line options.',
   usage        => "$PROGRAM_NAME <options>"
);
$o->_parse_specs(
   { spec  => 'user=s', desc  => 'User',                         },
   { spec  => 'dog|d',    desc  => 'dog option', group => 'Dogs',  },
   { spec  => 'cat|c',    desc  => 'cat option', group => 'Cats',  },
);
@ARGV = qw(--user foo --dog);
$o->get_opts();

my $o_clone = $o->clone();
isa_ok(
   $o_clone,
   'OptionParser'
);
ok(
   $o_clone->has('user') && $o_clone->has('dog') && $o_clone->has('cat'),
   'Clone has same opts'
);

$o_clone->set('user', 'Bob');
is(
   $o->get('user'),
   'foo',
   'Change to clone does not change original'
);

# #############################################################################
# Test issues. Any other tests should find their proper place above.
# #############################################################################

# #############################################################################
# Issue 140: Check that new style =item --[no]foo works like old style:
#    =item --foo
#    negatable: yes
# #############################################################################
@opt_specs = $o->_pod_to_specs("$trunk/t/lib/samples/pod/pod_sample_issue_140.txt");
is_deeply(
   \@opt_specs,
   [
      { spec => 'foo',   desc => 'Basic foo',         group => 'default', attributes => {} },
      { spec => 'bar!',  desc => 'New negatable bar', group => 'default', attributes => { negatable => 1 } },
   ],
   'New =item --[no]foo style for negatables'
);

# #############################################################################
# Issue 92: extract a paragraph from POD.
# #############################################################################
is(
   $o->read_para_after("$trunk/t/lib/samples/pod/pod_sample_issue_92.txt", qr/magic/),
   'This is the paragraph, hooray',
   'read_para_after'
);

# The first time I wrote this, I used the /o flag to the regex, which means you
# always get the same thing on each subsequent call no matter what regex you
# pass in.  This is to test and make sure I don't do that again.
is(
   $o->read_para_after("$trunk/t/lib/samples/pod/pod_sample_issue_92.txt", qr/abracadabra/),
   'This is the next paragraph, hooray',
   'read_para_after again'
);

# #############################################################################
# Issue 231: read configuration files
# #############################################################################
is_deeply(
   [$o->_read_config_file("$trunk/t/lib/samples/config_file_1.conf")],
   ['--foo', 'bar', '--verbose', '/path/to/file', 'h=127.1,P=12346'],
   'Reads a config file',
);

$o = new OptionParser(
   description  => 'OptionParser.t parses command line options.',
   usage        => "$PROGRAM_NAME <options>"
);
$o->_parse_specs(
   { spec  => 'config=A', desc  => 'Read this comma-separated list of config '
            . 'files (must be the first option on the command line).',  },
   { spec  => 'cat=A',    desc  => 'cat option (default a,b)',  },
);

is_deeply(
   [$o->get_defaults_files()],
   ["/etc/percona-toolkit/percona-toolkit.conf",
    "/etc/percona-toolkit/OptionParser.t.conf",
    "$ENV{HOME}/.percona-toolkit.conf",
    "$ENV{HOME}/.OptionParser.t.conf"],
   "default options files",
);
ok(!$o->got('config'), 'Did not got --config');

$o = new OptionParser(
   description  => 'OptionParser.t parses command line options.',
   usage        => "$PROGRAM_NAME <options>"
);
$o->_parse_specs(
   { spec  => 'config=A', desc  => 'Read this comma-separated list of config '
            . 'files (must be the first option on the command line).',  },
   { spec  => 'cat=A',    desc  => 'cat option (default a,b)',  },
);

$o->get_opts();
ok(
   check_usage($o, "help009.txt"),
   'Sets special config file default value',
);

@ARGV=qw(--config /path/to/config --cat);
$o = new OptionParser(
   description  => 'OptionParser.t parses command line options.',
   usage        => "$PROGRAM_NAME <options>"
);

$o->_parse_specs(
   { spec  => 'config=A', desc  => 'Read this comma-separated list of config '
            . 'files (must be the first option on the command line).',  },
   { spec  => 'cat',     desc  => 'cat option',  },
);
eval { $o->get_opts(); };
like($EVAL_ERROR, qr/Cannot open/, 'No config file found');

@ARGV = ('--config',"$trunk/t/lib/samples/empty",'--cat');
$o->get_opts();
ok($o->got('config'), 'Got --config');

ok(
   check_usage($o, "help010.txt"),
   'Parses special --config option first',
);

@ARGV = ("--config=$trunk/t/lib/samples/empty",'--cat');
$o->get_opts();
ok($o->got('config'), 'Got --config=');

$o = new OptionParser(
   description  => 'OptionParser.t parses command line options.',
   usage        => "$PROGRAM_NAME <options>"
);
$o->_parse_specs(
   { spec  => 'config=A', desc  => 'Read this comma-separated list of config '
      . 'files (must be the first option on the command line).',  },
   { spec  => 'cat',     desc  => 'cat option',  },
);

@ARGV=qw(--cat --config /path/to/config);
{
   local *STDERR;
   open STDERR, '>', '/dev/null';
   $o->get_opts();
}
is_deeply(
   $o->errors(),
   ['Error parsing options', 'Unrecognized command-line options /path/to/config'],
   'special --config option not given first',
);

# And now we can actually get it to read a config file into the options!
$o = new OptionParser(
   description  => 'OptionParser.t parses command line options.',
   usage        => "$PROGRAM_NAME <options>",
);
is($o->{strict}, 1, "Strict mode enabled by default");
$o->_parse_specs(
   "This tool accepts additional command-line arguments.  Refer to the synopsis and usage information for details.",
   { spec  => 'config=A', desc  => 'Read this comma-separated list of config '
      . 'files (must be the first option on the command line).',  },
   { spec  => 'foo=s',     desc  => 'foo option',  },
   { spec  => 'verbose+',  desc  => 'increase verbosity',  },
);
is($o->{strict}, 0, "Special rule disables strict mode");

@ARGV = ('--config', "$trunk/t/lib/samples/config_file_1.conf");
$o->get_opts();
is_deeply(
   [@ARGV],
   ['/path/to/file', 'h=127.1,P=12346'],
   'Config file influences @ARGV',
);
ok($o->got('foo'), 'Got --foo');
is($o->get('foo'), 'bar', 'Got --foo value');
ok($o->got('verbose'), 'Got --verbose');
is($o->get('verbose'), 1, 'Got --verbose value');

@ARGV = ('--config', "$trunk/t/lib/samples/config_file_1.conf,$trunk/t/lib/samples/config_file_2.conf");
$o->get_opts();
is_deeply(
   [@ARGV],
   ['/path/to/file', 'h=127.1,P=12346', '/path/to/file'],
   'Second config file influences @ARGV',
);
ok($o->got('foo'), 'Got --foo again');
is($o->get('foo'), 'baz', 'Got overridden --foo value');
ok($o->got('verbose'), 'Got --verbose twice');
is($o->get('verbose'), 2, 'Got --verbose value twice');

# #############################################################################
# Issue 409: OptionParser modifies second value of
# ' -- .*','(\w+): ([^,]+)' for array type opt
# #############################################################################
$o = new OptionParser(
   description  => 'OptionParser.t parses command line options.',
   usage        => "$PROGRAM_NAME <options>"
);
$o->_parse_specs(
   { spec => 'foo=a', desc => 'foo' },
);
@ARGV = ('--foo', ' -- .*,(\w+): ([^\,]+)');
$o->get_opts();
is_deeply(
   $o->get('foo'),
   [
      ' -- .*',
      '(\w+): ([^\,]+)',
   ],
   'Array of vals with internal commas (issue 409)'
);

# #############################################################################
# Issue 349: Make OptionParser die on unrecognized attributes
# #############################################################################
$o = new OptionParser(
   description  => 'OptionParser.t parses command line options.',
   usage        => "$PROGRAM_NAME <options>"
);
eval { $o->get_specs("$trunk/t/lib/samples/pod/pod_sample_06.txt"); };
like(
   $EVAL_ERROR,
   qr/Unrecognized attribute for --verbose: culumative/,
   'Die on unrecognized attribute'
);


# #############################################################################
# Issue 460: mk-archiver does not inherit DSN as documented
# #############################################################################

# The problem is actually in how OptionParser handles copying DSN vals.
$o = new OptionParser(
   description  => 'OptionParser.t parses command line options.',
   usage        => "$PROGRAM_NAME <options>"
);
# Hack DSNParser into OptionParser.  This is just for testing.
$o->{DSNParser} = $dp;
$o->_parse_specs(
   { spec  => 'source=d',   desc  => 'source',   },
   { spec  => 'dest=d',     desc  => 'dest',     },
   'DSN values in --dest default to values from --source if COPY is yes.',
);
@ARGV = (
   '--source', 'h=127.1,P=12345,D=test,u=bob,p=foo',
   '--dest', 'P=12346',
);
$o->get_opts();
my $dest_dsn = $o->get('dest');
is_deeply(
   $dest_dsn,
   {
      A => undef,
      D => 'test',
      F => undef,
      P => '12346',
      S => undef,
      h => '127.1',
      p => 'foo',
      u => 'bob',
   },
   'Copies DSN values correctly (issue 460)'
);

# #############################################################################
# Issue 248: Add --user, --pass, --host, etc to all tools
# #############################################################################

# See the 5 cases (i.-v.) at http://groups.google.com/group/maatkit-discuss/browse_thread/thread/f4bf1e659c60f03e

# case ii.
$o = new OptionParser(
   description  => 'OptionParser.t parses command line options.',
   usage        => "$PROGRAM_NAME <options>"
);
# Hack DSNParser into OptionParser.  This is just for testing.
$o->{DSNParser} = $dp;
$o->get_specs("$trunk/bin/pt-archiver");
@ARGV = (
   '--source',    'h=127.1,S=/tmp/mysql.socket',
   '--port',      '12345',
   '--user',      'bob',
   '--password',  'foo',
   '--socket',    '/tmp/bad.socket',  # should *not* override DSN
   '--where',     '1=1',   # required
);
$o->get_opts();
my $src_dsn = $o->get('source');
is_deeply(
   $src_dsn,
   {
      a => undef,
      A => undef,
      b => undef,
      D => undef,
      F => undef,
      i => undef,
      m => undef,
      P => '12345',
      S => '/tmp/mysql.socket',
      h => '127.1',
      p => 'foo',
      t => undef,
      u => 'bob',
      L => undef,
   },
   'DSN opt gets missing vals from --host, --port, etc. (issue 248)',
);

$o = new OptionParser(
   description  => 'OptionParser.t parses command line options.',
   usage        => "$PROGRAM_NAME <options>"
);
# Hack DSNParser into OptionParser.  This is just for testing.
$o->{DSNParser} = $dp;
$o->get_specs("$trunk/bin/pt-archiver");
# Like case ii. but make sure --dest copies u from --source, not --user.
@ARGV = (
   '--source',    'h=127.1,u=bob',
   '--dest',      'h=127.1',
   '--user',      'wrong_user',
   '--where',     '1=1',   # required
);
$o->get_opts();
$dest_dsn = $o->get('dest');
is_deeply(
   $dest_dsn,
   {
      a => undef,
      A => undef,
      b => undef,
      D => undef,
      F => undef,
      i => undef,
      m => undef,
      P => undef,
      S => undef,
      h => '127.1',
      p => undef,
      t => undef,
      u => 'bob',
      L => undef,
   },
   'Vals from "defaults to" DSN take precedence over defaults (issue 248)'
);


# #############################################################################
#  Issue 617: Command line options do no override config file options
# #############################################################################
diag(`echo "iterations=4" > ~/.OptionParser.t.conf`);
$o = new OptionParser(
   description  => 'OptionParser.t parses command line options.',
   usage        => "$PROGRAM_NAME <options>"
);
$o->get_specs("$trunk/bin/pt-query-digest");
@ARGV = (qw(--iterations 9));
$o->get_opts();
is(
   $o->get('iterations'),
   9,
   'Cmd line opt overrides conf (issue 617)'
);
diag(`rm -rf ~/.OptionParser.t.conf`);

# #############################################################################
#  Issue 623: --since +N does not work in mk-parallel-dump
# #############################################################################

# time type opts need to allow leading +/-
$o = new OptionParser(
   description  => 'OptionParser.t parses command line options.',
   usage        => "$PROGRAM_NAME <options>"
);
$o->get_specs("$trunk/bin/pt-query-digest");
@ARGV = (qw(--run-time +9));
$o->get_opts();
is(
   $o->get('run-time'),
   '+9',
   '+N time value'
);

@ARGV = (qw(--run-time -7));
$o->get_opts();
is(
   $o->get('run-time'),
   '-7',
   '-N time value'
);

@ARGV = (qw(--run-time +1m));
$o->get_opts();
is(
   $o->get('run-time'),
   '+60',
   '+N time value with suffix'
);


# #############################################################################
# Issue 829: maatkit: mk-query-digest.1p : provokes warnings from man
# #############################################################################
# This happens because --ignore-attributes has a really long default
# value like val,val,val.  man can't break this line unless that list
# has spaces like val, val, val.
$o = new OptionParser(
   description  => 'OptionParser.t parses command line options.',
   usage        => "$PROGRAM_NAME <options>"
);
$o->_parse_specs(
   { spec  => 'foo=a',   desc => 'foo (default arg, cmd, ip, port)' },
);
@ARGV = ();
$o->get_opts();
is_deeply(
   $o->get('foo'),
   [qw(arg cmd ip port)],
   'List vals separated by spaces'
);


# #############################################################################
# Issue 940: OptionParser cannot resolve option dependencies
# #############################################################################
$o = new OptionParser(
   description  => 'OptionParser.t parses command line options.',
   usage        => "$PROGRAM_NAME <options>"
);
# Hack DSNParser into OptionParser.  This is just for testing.
$o->{DSNParser} = $dp;
$o->_parse_specs(
   { spec => 'foo=d', desc => 'DSN foo' },
   { spec => 'bar=d', desc => 'DSN bar' },
   'DSN values in --foo default to values in --bar if COPY is yes.',
);
# This simulates what get_opts() does but allows us to call
# _check_opts() manually with foo first.
$o->{opts}->{bar} = {
   long  => 'bar',
   value => 'D=DB,u=USER,h=localhost',
   got   => 1,
   type  => 'd',
};
$o->{opts}->{foo} = {
   long  => 'foo',
   value => 'h=otherhost',
   got   => 1,
   type  => 'd',
};
$o->_check_opts(qw(foo bar));
is_deeply(
   $o->get('foo'),
   {
      D => 'DB',
      u => 'USER',
      S => undef,
      F => undef,
      P => undef,
      h => 'otherhost',
      p => undef,
      A => undef,
   },
   'Resolves dependency'
);

# Should die on circular dependency, avoid infinite loop.
$o = new OptionParser(
   description  => 'OptionParser.t parses command line options.',
   usage        => "$PROGRAM_NAME <options>"
);
$o->_parse_specs(
   { spec => 'foo=d', desc => 'DSN foo' },
   { spec => 'bar=d', desc => 'DSN bar' },
   'DSN values in --foo default to values in --bar if COPY is yes.',
   'DSN values in --bar default to values in --foo if COPY is yes.',
);
$o->{opts}->{bar} = {
   long  => 'bar',
   value => 'D=DB,u=USER,h=localhost',
   got   => 1,
   type  => 'd',
};
$o->{opts}->{foo} = {
   long  => 'foo',
   value => 'h=otherhost',
   got   => 1,
   type  => 'd',
};

throws_ok(
   sub { $o->_check_opts(qw(foo bar)) },
   qr/circular dependencies/,
   'Dies on circular dependency'
);


# #############################################################################
# Issue 344
# #############################################################################
$o = new OptionParser(
   description  => 'OptionParser.t parses command line options.',
   usage        => "$PROGRAM_NAME <options>"
);
$o->_parse_specs(
   { spec  => 'foo=z',   desc => 'foo' },
);
@ARGV = qw(--foo null);
$o->get_opts();
is(
   $o->get('foo'),
   'null',
   'NULL size'
);

# #############################################################################
# Issue 55: Integrate DSN specifications into POD
# #############################################################################
$o = new OptionParser(
   description  => 'OptionParser.t parses command line options.',
   usage        => "$PROGRAM_NAME <options>"
);
$o->get_specs("$trunk/t/lib/samples/pod/pod_sample_dsn.txt");

ok(
   $o->DSNParser(),
   'Auto-created DNSParser obj'
);

@ARGV = ();
$o->get_opts();
like(
   $o->print_usage(),
   qr/z\s+no\s+/,
   'copy: no'
);

# #############################################################################
# Issue 1123: OptionParser type: string; default: 0 doesn't work
# #############################################################################
$o = new OptionParser(
   description  => 'OptionParser.t parses command line options.',
   usage        => "$PROGRAM_NAME <options>"
);
$o->get_specs("$trunk/bin/pt-fifo-split");
@ARGV = ();
$o->get_opts();
is(
   $o->get('offset'),
   0,
   "type: string; default: 0 (issue 1123)"
);


# #############################################################################
# Issue 338: Make all of tool's --help output come from POD
# #############################################################################
$o = new OptionParser(file => "$trunk/bin/pt-archiver");

my %synop  = $o->_parse_synopsis();

is_deeply(
   \%synop,
   {
      usage       => "pt-archiver [OPTIONS] --source DSN --where WHERE",
      description => "pt-archiver nibbles records from a MySQL table.  The --source and --dest arguments use DSN syntax; if COPY is yes, --dest defaults to the key's value from --source.",
   },
   "_parse_synopsis() gets usage and description"
);

@ARGV = qw(--help);
$o->get_specs();
$o->get_opts();
$output = output(
   sub { $o->usage_or_errors(undef, 1); },
);
$synop{usage} =~ s/([\[\]])/\\$1/g;
like(
   $output,
   qr/^$synop{description}  For more details.+\nUsage: $synop{usage}$/m,
   "Uses desc and usage from SYNOPSIS for help"
);

# #############################################################################
# Bug 1039074: Tools exit 0 on error parsing options, should exit non-zero
# #############################################################################

# pt-archiver requires at least one of --dest, --file or --purge, as well as
# --where and --source.  So specifying no options should cause errors.
@ARGV = qw();
$o = new OptionParser(file => "$trunk/bin/pt-archiver");
$o->get_specs();
$o->get_opts();

my $exit_status = 0;
($output, $exit_status) = full_output(
   sub { $o->usage_or_errors("$trunk/bin/pt-archiver"); },
);

is(
   $exit_status,
   1,
   "Non-zero exit status on error parsing options (bug 1039074)"
);


# #############################################################################
# --set-vars/set_vars()
# #############################################################################

@ARGV = qw();
$o = new OptionParser(file => "$trunk/bin/pt-archiver");
$o->get_specs();
$o->get_opts();

my $vars = $o->set_vars("$trunk/bin/pt-archiver");
is_deeply(
   $vars,
   {
      wait_timeout => {
         default => 1,
         val     => '10000',
      },
   }, 
   "set_vars(): 1 default from docs"
) or diag(Dumper($vars));

# Bug 1182856: Zero values causes "Invalid --set-vars value: var=0"
@ARGV = qw(--set-vars SQL_LOG_BIN=0);
$o->get_opts();

$vars = $o->set_vars("$trunk/bin/pt-archiver");
is_deeply(
   $vars,
   {
      wait_timeout => {
         default => 1,
         val     => '10000',
      },
      SQL_LOG_BIN => {
         default  => 0,
         val      => '0',
      },
   }, 
   "set_vars(): var=0 (bug 1182856)"
) or diag(Dumper($vars));


# #############################################################################
# https://bugs.launchpad.net/percona-toolkit/+bug/1199589
# pt-archiver deletes data despite --dry-run
# #############################################################################

# From the issue: "One problem is that --optimize is not being used correctly:
# the option takes an argument: d, s, or ds (see --analyze). The real problem
# is that --optimize is consuming the next option, which is --dry-run in this
# case. This shouldn't happen; it means the option parser is failing to notice
# that --dry-run is not the string val to --optimize but rather an option;
# it should catch this and the tool should fail to start with an error like
# "--optimize requires a value".

@ARGV = qw(--optimize --dry-run --ascend-first --where 1=1 --purge --source localhost);
$o = new OptionParser(file => "$trunk/bin/pt-archiver");
$o->get_specs();
$o->get_opts();

$output = output(
   sub { $o->usage_or_errors(undef, 1); },
);

like(
   $output,
   qr/--optimize requires a string value/,
   "String opts don't consume the next opt (bug 1199589)"
);

is(
   $o->get('optimize'),
   undef,
   "--optimize didn't consume --dry-run (bug 1199589)"
);

@ARGV = qw(--optimize ds --dry-run --ascend-first --where 1=1 --purge --source localhost);
$o->get_opts();

$output = output(
   sub { $o->usage_or_errors(undef, 1); },
);

is(
   $output,
   '',
   "String opts still work (bug 1199589)"
);

is(
   $o->get('optimize'),
   'ds',
   "--optimize got its value (bug 1199589)"
);


# #############################################################################
# Issue 1290911 : prompt_noecho should send prompt to STDERR so user can 
# direct STDOUT to a file and still see the prompt
# #############################################################################

SKIP: {
   eval {require Term::ReadKey};
   skip ('\'prompt_no_echo outputs to STDERR\' because Term::ReadKey not available', 1) if $EVAL_ERROR;

$o = new OptionParser();

$output = output(  
      sub { 
         my $input = "thepassword";
         local *STDIN;
         open STDIN, '<', \$input;
         $o->prompt_noecho('Test Prompt:'); },

      stderr=>1,
   );

is (
   $output,
   "Test Prompt:\n",
   'prompt_no_echo outputs prompt to STDERR'
);

} # end skip

# #############################################################################
#  Issue 1361293: Global config file with no-version-check option makes tools
#  that don't recognize the option fail.
# #############################################################################
diag(`echo "no-version-check" > ~/.OptionParser.t.conf`);
$o = new OptionParser(
   description  => 'OptionParser.t parses command line options.',
   usage        => "$PROGRAM_NAME <options>"
);
$o->get_specs("$trunk/bin/pt-slave-find"),   # doesn't have version-check option
$output = output(  
         sub {
            $o->get_opts();
         },
         stderr=>1
      );
unlike(
   $output,
   qr/Unknown option: no-version-check/,
   'no-version-check ignored if unsupported and in config file. issue 1361293'
);
diag(`rm -rf ~/.OptionParser.t.conf`);



# #############################################################################
# Done.
# #############################################################################
{
   local *STDERR;
   open STDERR, '>', \$output;
   $o->_d('Complete test coverage');
}
like(
   $output,
   qr/Complete test coverage/,
   '_d() works'
);

done_testing;
exit;




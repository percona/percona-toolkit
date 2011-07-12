#!/usr/bin/perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More tests => 87;

use PerconaTest;
use PodParser;
use AdvisorRules;
use QueryAdvisorRules;
use Advisor;
use SQLParser;

# This test should just test that the QueryAdvisor module conforms to the
# expected interface:
#   - It has a get_rules() method that returns a list of hashrefs:
#     ({ID => 'ID', code => $code}, {ID => ..... }, .... )
#   - It has a load_rule_info() method that accepts a list of hashrefs, which
#     we'll use to load rule info from POD.  Our built-in rule module won't
#     store its own rule info.  But plugins supplied by users should.
#   - It has a get_rule_info() method that accepts an ID and returns a hashref:
#     {ID => 'ID', Severity => 'NOTE|WARN|CRIT', Description => '......'}
my $p   = new PodParser();
my $qar = new QueryAdvisorRules(PodParser => $p);

my @rules = $qar->get_rules();
ok(
   scalar @rules,
   'Returns array of rules'
);

my $rules_ok = 1;
foreach my $rule ( @rules ) {
   if (    !$rule->{id}
        || !$rule->{code}
        || (ref $rule->{code} ne 'CODE') )
   {
      $rules_ok = 0;
      last;
   }
}
ok(
   $rules_ok,
   'All rules are proper'
);

# QueryAdvisorRules.pm has more rules than mqa-rule-LIT.001.pod so to avoid
# "There is no info" errors we remove all but LIT.001.
@rules = grep { $_->{id} eq 'LIT.001' } @rules;

# Test that we can load rule info from POD.  Make a sample POD file that has a
# single sample rule definition for LIT.001 or something.
$qar->load_rule_info(
   rules    => \@rules,
   file     => "$trunk/t/lib/samples/pod/mqa-rule-LIT.001.pod",
   section  => 'RULES',
);

# We shouldn't be able to load the same rule info twice.
throws_ok(
   sub {
      $qar->load_rule_info(
         rules    => \@rules,
         file     => "$trunk/t/lib/samples/pod/mqa-rule-LIT.001.pod",
         section  => 'RULES',
      );
   },
   qr/Rule \S+ is already defined/,
   'Duplicate rule info is caught'
);

# Test that we can now get a hashref as described above.
is_deeply(
   $qar->get_rule_info('LIT.001'),
   {  id          => 'LIT.001',
      severity    => 'note',
      description => "IP address used as string.  The string literal looks like an IP address but is not used inside INET_ATON().  WHERE ip='127.0.0.1' is better as ip=INET_ATON('127.0.0.1') if the column is numeric.",
   },
   'get_rule_info(LIT.001) works',
);

# Test getting a nonexistent rule.
is(
   $qar->get_rule_info('BAR.002'),
   undef,
   "get_rule_info() nonexistent rule"
);

is(
   $qar->get_rule_info(),
   undef,
   "get_rule_info(undef)"
);

# Add a rule for which there is no POD info and test that it's not allowed.
push @rules, {
   id   => 'FOO.001',
   code => sub { return },
};
$qar->_reset_rule_info();  # else we'll get "cannot redefine rule" error
throws_ok (
   sub {
      $qar->load_rule_info(
         rules    => \@rules,
         file     => "$trunk/t/lib/samples/pod/mqa-rule-LIT.001.pod",
         section  => 'RULES',
      );
   },
   qr/There is no info for rule FOO.001/,
   "Doesn't allow rules without info",
);

# ###########################################################################
# Test cases for the rules themselves.
# ###########################################################################
my @cases = (
   {  name   => 'IP address not inside INET_ATON, plus SELECT * is used',
      query  => 'SELECT * FROM tbl WHERE ip="127.0.0.1"',
      advice => [qw(COL.001 LIT.001)],
      pos    => [0, 37],
   },
   {  name   => 'Date literal not quoted',
      query  => 'SELECT col FROM tbl WHERE col < 2001-01-01',
      advice => [qw(LIT.002)],
   },
   {  name   => 'Aliases without AS keyword',
      query  => 'SELECT a b FROM tbl',
      advice => [qw(ALI.001 CLA.001)],
   },
   {  name   => 'tbl.* alias',
      query  => 'SELECT tbl.* foo FROM bar WHERE id=1',
      advice => [qw(ALI.001 ALI.002 COL.001)],
   },
   {  name   => 'tbl as tbl',
      query  => 'SELECT col FROM tbl AS tbl WHERE id=1',
      advice => [qw(ALI.003)],
   },
   {  name   => 'col as col',
      query  => 'SELECT col AS col FROM tbl AS `my tbl` WHERE id=1',
      advice => [qw(ALI.003)],
   },
   {  name   => 'Blind INSERT',
      query  => 'INSERT INTO tbl VALUES(1),(2)',
      advice => [qw(COL.002)],
   },
   {  name   => 'Blind INSERT',
      query  => 'INSERT tbl VALUE (1)',
      advice => [qw(COL.002)],
   },
   {  name   => 'SQL_CALC_FOUND_ROWS',
      query  => 'SELECT SQL_CALC_FOUND_ROWS col FROM tbl AS alias WHERE id=1',
      advice => [qw(KWR.001)],
   },
   {  name   => 'All comma joins ok',
      query  => 'SELECT col FROM tbl1, tbl2 WHERE tbl1.id=tbl2.id',
      advice => [],
   },
   {  name   => 'All ANSI joins ok',
      query  => 'SELECT col FROM tbl1 JOIN tbl2 USING(id) WHERE tbl1.id>10',
      advice => [],
   },
   {  name   => 'Mix comman/ANSI joins',
      query  => 'SELECT col FROM tbl, tbl1 JOIN tbl2 USING(id) WHERE tbl.d>10',
      advice => [qw(JOI.001)],
   },
   {  name   => 'Non-deterministic GROUP BY',
      query  => 'select a, b, c from tbl where foo="bar" group by a',
      advice => [qw(RES.001)],
   },
   {  name   => 'Non-deterministic LIMIT w/o ORDER BY',
      query  => 'select a, b from tbl where foo="bar" limit 10 group by a, b',
      advice => [qw(RES.002)],
   },
   {  name   => 'ORDER BY RAND()',
      query  => 'select a from t where id=1 order by rand()',
      advice => [qw(CLA.002)],
   },
   {  name   => 'ORDER BY RAND(N)',
      query  => 'select a from t where id=1 order by rand(123)',
      advice => [qw(CLA.002)],
   },
   {  name   => 'LIMIT w/ OFFSET does not scale',
      query  => 'select a from t where i=1 limit 10, 10 order by a',
      advice => [qw(CLA.003)],
   },
   {  name   => 'LIMIT w/ OFFSET does not scale',
      query  => 'select a from t where i=1 limit 10 OFFSET 10 order by a',
      advice => [qw(CLA.003)],
   },
   {  name   => 'Leading %wildcard',
      query  => 'select a from t where i like "%hm"',
      advice => [qw(ARG.001)],
   },
   {  name   => 'Leading _wildcard',
      query  => 'select a from t where i LIKE "_hm"',
      advice => [qw(ARG.001)],
   },
   {  name   => 'Leading "% wildcard"',
      query  => 'select a from t where i like "% eh "',
      advice => [qw(ARG.001)],
   },
   {  name   => 'Leading "_ wildcard"',
      query  => 'select a from t where i LIKE "_ eh "',
      advice => [qw(ARG.001)],
   },
   {  name   => 'GROUP BY number',
      query  => 'select a from t where i <> 4 group by 1',
      advice => [qw(CLA.004)],
   },
   {  name   => '!= instead of <>',
      query  => 'select a from t where i != 2',
      advice => [qw(STA.001)],
   },
   {  name   => "LIT.002 doesn't match",
      query  => "update foo.bar set biz = '91848182522'",
      advice => [],
   },
   {  name   => "LIT.002 doesn't match",
      query  => "update db2.tuningdetail_21_265507 inner join db1.gonzo using(g) set n.c1 = a.c1, n.w3 = a.w3",
      advice => [],
   },
   {  name   => "LIT.002 doesn't match",
      query  => "UPDATE db4.vab3concept1upload
                 SET    vab3concept1id = '91848182522'
                 WHERE  vab3concept1upload='6994465'",
      advice => [],
   },
   {  name   => "LIT.002 at end of query",
      query  => "select c from t where d=2006-10-10",
      advice => [qw(LIT.002)],
   },
   {  name   => "LIT.002 5 digits doesn't match",
      query  => "select c from t where d=12345",
      advice => [],
   },
   {  name   => "LIT.002 7 digits doesn't match",
      query  => "select c from t where d=1234567",
      advice => [],
   },
   {  name   => "SELECT var LIMIT",
      query  => "select \@\@version_comment limit 1 ",
      advice => [],
   },
   {  name   => "Date with time",
      query  => "select c from t where d > 2010-03-15 09:09:09",
      advice => [qw(LIT.002)],
   },
   {  name   => "Date with time and subseconds",
      query  => "select c from t where d > 2010-03-15 09:09:09.123456",
      advice => [qw(LIT.002)],
   },
   {  name   => "Date with time doesn't match",
      query  => "select c from t where d > '2010-03-15 09:09:09'",
      advice => [qw()],
   },
   {  name   => "Date with time and subseconds doesn't match",
      query  => "select c from t where d > '2010-03-15 09:09:09.123456'",
      advice => [qw()],
   },
   {  name   => "Short date",
      query  => "select c from t where d=73-03-15",
      advice => [qw(LIT.002)],
   },
   {  name   => "Short date with time",
      query  => "select c from t where d > 73-03-15 09:09:09",
      advice => [qw(LIT.002)],
      pos    => [34],
   },
   {  name   => "Short date with time and subseconds",
      query  => "select c from t where d > 73-03-15 09:09:09.123456",
      advice => [qw(LIT.002)],
   },
   {  name   => "Short date with time doesn't match",
      query  => "select c from t where d > '73-03-15 09:09:09'",
      advice => [qw()],
   },
   {  name   => "Short date with time and subseconds doesn't match",
      query  => "select c from t where d > '73-03-15 09:09:09.123456'",
      advice => [qw()],
   },
   {  name   => "LIKE without wildcard",
      query  => "select c from t where i like 'lamp'",
      advice => [qw(ARG.002)],
   },
   {  name   => "LIKE without wildcard, 2nd arg",
      query  => "select c from t where i like 'lamp%' or i like 'foo'",
      advice => [qw(ARG.002)],
   },
   {  name   => "LIKE with wildcard %",
      query  => "select c from t where i like 'lamp%'",
      advice => [qw()],
   },
   {  name   => "LIKE with wildcard _",
      query  => "select c from t where i like 'lamp_'",
      advice => [qw()],
   },
   {  name   => "Issue 946: LIT.002 false-positive",
      query  => "delete from t where d in('MD6500-26', 'MD6500-21-22', 'MD6214')",
      advice => [qw()],
   },
   {  name   => "Issue 946: LIT.002 false-positive",
      query  => "delete from t where d in('FS-8320-0-2', 'FS-800-6')",
      advice => [qw()],
   },
# This matches LIT.002 but unless the regex gets really complex or
# we do this rule another way, this will have to remain an exception.
#   {  name   => "Issue 946: LIT.002 false-positive",
#      query  => "select c from t where c='foo 2010-03-17 bar'",
#      advice => [qw()],
#   },

   {  name   => "IN(subquer)",
      query  => "select c from t where i in(select d from z where 1)",
      advice => [qw(SUB.001)],
      pos    => [33],
   },
   {  name   => "JOI.002",
      query  => "select c from `w_chapter` INNER JOIN `w_series` AS `w_chapter__series` ON `w_chapter`.`series_id` = `w_chapter__series`.`id`, `w_series`, `auth_user` where id=1",
      advice => [qw(JOI.001 JOI.002)],
   },
   {  name   => "JOI.002 ansi self-join ok",
      query  => "select c from employees as e join employees as s on e.supervisor = s.id where foo='bar'",
      advice => [],
   },
   {  name   => "JOI.002 ansi self-join with other joins ok",
      query  => "select c from employees as e join employees as s on e.supervisor = s.id join employees as r on s.id = r.foo where foo='bar'",
      advice => [],
   },
   {  name   => "JOI.002 comma self-join ok",
      query  => "select c from employees as e, employees as s where e.supervisor = s.id",
      advice => [],
   },
   {  name   => "CLA.005 ORDER BY col=<constant>",
      query  => "select col1, col2 from tbl where col3=5 order by col3, col4",
      advice => [qw(CLA.005)],
   },
   # Now col3 is not a constant, it's the string '5'.
   {  name   => "CLA.005 not tricked by '5'",
      query  => "select col1, col2 from tbl where col3='5' order by col3, col4",
      advice => [],
   },
   {  name   => "JOI.003",
      query  => "select c from L left join R using(c) where L.a=5 and R.b=10",
      advice => [qw(JOI.003)],
   },
   {  name   => "JOI.003 ok with IS NULL",
      query  => "select c from L left join R using(c) where L.a=5 and R.c is null",
      advice => [],
   },
   {  name   => "JOI.003 ok without outer table column",
      query  => "select c from L left join R using(c) where L.a=5",
      advice => [],
   },
   {  name   => "JOI.003 RIGHT",
      query  => "select c from L right join R using(c) where R.a=5 and L.b=10",
      advice => [qw(JOI.003)],
   },
   {  name   => "JOI.003 RIGHT ok with IS NULL",
      query  => "select c from L right join R using(c) where R.a=5 and L.c is null",
      advice => [],
   },
   {  name   => "JOI.003 RIGHT ok without outer table column",
      query  => "select c from L right join R using(c) where R.a=5",
      advice => [],
   },
   {  name   => "JOI.003 ok with INNER JOIN",
      query  => "select c from L inner join R using(c) where R.a=5 and L.b=10",
      advice => [],
   },
   {  name   => "JOI.003 ok with JOIN",
      query  => "select c from L join R using(c) where R.a=5 and L.b=10",
      advice => [],
   },
   {  name   => "JOI.004",
      query  => "select c from L left join R on a=b where L.a=5 and R.c is null",
      tbl_structs => {
         db => {
            L => { name => 'L', is_col => { a => 1         } },
            R => { name => 'R', is_col => { b => 1, c => 1 } },
         },
      },
      advice => [qw(JOI.004)],
   },
   {  name   => "JOI.004 USING (b)",
      query  => "select c from L left join R using(b) where L.a=5 and R.c is null",
      advice => [qw(JOI.004)],
   },
   {  name   => "JOI.004 without table info",
      query  => "select c from L left join R on a=b where L.a=5 and R.c is null",
      advice => [qw(JOI.004)],
   },
   {  name   => "JOI.004 good exclusion join",
      query  => "select c from L left join R on a=b where L.a=5 and R.b is null",
      tbl_structs => {
         db => {
            L => { name => 'L', is_col => { a => 1         } },
            R => { name => 'R', is_col => { b => 1, c => 1 } },
         },
      },
      advice => [],
   },
   {  name   => "JOI.004 RIGHT",
      query  => "select c from L right join R on a=b where R.a=5 and L.c is null",
      tbl_structs => {
         db => {
            L => { name => 'L', is_col => { a => 1, c => 1 } },
            R => { name => 'R', is_col => { b => 1,        } },
         },
      },
      advice => [qw(JOI.004)],
   },
   {  name   => "JOI.004 can table-qualify cols from WHERE",
      query  => "select c from L left join R on a=b where a=5 and c is null",
      tbl_structs => {
         db => {
            L => { name => 'L', is_col => { a => 1         } },
            R => { name => 'R', is_col => { b => 1, c => 1 } },
         },
      },
      advice => [qw(JOI.004)],
   },
   {  name   => "CLA.006 GROUP BY different tables",
      query  => "select id from tbl1 join tbl2 using(a) where 1 group by tbl1.id, tbl2.id",
      advice => [qw(CLA.006)],
   },
   {  name   => "CLA.006 ORDER BY different tables",
      query  => "select id from tbl1 join tbl2 using(a) where 1 order by tbl1.id, tbl2.id",
      advice => [qw(CLA.006)],
   },
   {  name   => "CLA.006 GROUP BY tbl_a ORDER BY tbl_b",
      query  => "select id from tbl1 join tbl2 using(a) where 1 group by tbl1.id order by tbl2.id",
      advice => [qw(CLA.006)],
   },
   {  name   => "CLA.006 GROUP BY tbl_a ORDER BY tbl_b (2)",
      query  => "select id, foo from tbl1 join tbl2 using(a) where 1 group by tbl1.id order by tbl2.id, tbl1.foo",
      advice => [qw(CLA.006 RES.001)],
   },
   {  name   => "CLA.006 GROUP BY tbl_a ORDER BY tbl_b (3)",
      query  => "select id,foo from tbl1 join tbl2 using(a) where 1 group by tbl1.id, tbl2.foo order by tbl2.id",
      advice => [qw(CLA.006)],
   },
   # CLA.006 cannot be detected without table qualifications for every column
   {  name   => "CLA.006 without full table qualifications",
      query  => "select id from tbl1 join tbl2 using(a) where 1 group by id order by tbl1.id",
      advice => [],
   },
   {
      name   => 'Issue 1163, ARG.001 false-positive',
      query  => "SELECT COUNT(*) FROM foo WHERE meta_key = '_edit_lock' AND post_id = 488",
      advice => [qw()],
   },
   {
      name   => 'Issue 1163, RES.001 false-positive',
      query  => "SELECT YEAR(post_date) AS `year`, MONTH(post_date) AS `month`, count(ID) as posts FROM foo_posts  WHERE post_type = 'post' AND post_status = 'publish' GROUP BY YEAR(post_date), MONTH(post_date) ORDER BY post_date DESC",
      advice => [qw()],
   },
   {
      name   => 'CLA.007 ORDER BY ASC and DESC',
      query  => "select col1, col2 from tbl where i=1 order by col1, col2 desc",
      advice => [qw(CLA.007)],
   },
);

# Run the test cases.
$qar = new QueryAdvisorRules(PodParser => $p);
$qar->load_rule_info(
   rules   => [ $qar->get_rules() ],
   file    => "$trunk/bin/pt-query-advisor",
   section => 'RULES',
);

my $adv = new Advisor(match_type => "pos");
$adv->load_rules($qar);
$adv->load_rule_info($qar);

my $sp = new SQLParser();

foreach my $test ( @cases ) {
   my $query_struct = $sp->parse($test->{query});
   my $event = {
      arg          => $test->{query},
      query_struct => $query_struct,
      tbl_structs  => $test->{tbl_structs},
   };
   my ($ids, $pos) = $adv->run_rules(
      event       => $event,
   );
   is_deeply(
      $ids,
      $test->{advice},
      $test->{name},
   );

   if ( $test->{pos} ) {
      is_deeply(
         $pos,
         $test->{pos},
         "$test->{name} matched near pos"
      );
   }

   # To help me debug.
   die if $test->{stop};
}

# #############################################################################
# Done.
# #############################################################################
my $output = '';
{
   local *STDERR;
   open STDERR, '>', \$output;
   $p->_d('Complete test coverage');
}
like(
   $output,
   qr/Complete test coverage/,
   '_d() works'
);
exit;

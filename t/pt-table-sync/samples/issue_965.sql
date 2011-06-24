drop database if exists issue_965;
create database issue_965;
use issue_965;

CREATE TABLE `t1` (
  `b_ref` varchar(20) NOT NULL default '',
  `r` int(11) NOT NULL default '0',
  `o_i` int(11) NOT NULL default '0',
  `r_s` datetime NOT NULL default '1970-01-01 00:00:00',
  PRIMARY KEY  (`b_ref`,`r`,`o_i`)
) ENGINE=MyISAM;

CREATE TABLE `t2` (
  `b_ref` varchar(20) NOT NULL default '',
  `r` int(11) NOT NULL default '0',
  `o_i` int(11) NOT NULL default '0',
  `r_s` datetime NOT NULL default '1970-01-01 00:00:00',
  PRIMARY KEY  (`b_ref`,`r`,`o_i`)
) ENGINE=MyISAM;

insert into t1 values
   ('aaa', 1, 1, '2010-03-29 14:44'),
   ('aab', 2, 1, '2010-03-29 14:44'),
   ('aac', 3, 1, '2010-03-29 14:44'),
   ('aad', 4, 1, '2010-03-29 14:44'),
   ('aae', 5, 1, '2010-03-29 14:44'),
   ('aaf', 6, 1, '2010-03-29 14:44'),
   ('aag', 7, 1, '2010-03-29 14:44'),
   ('aah', 8, 1, '2010-03-29 14:44');

insert into t2 values
   ('aaa', 1, 1, '2010-03-29 14:44'),
   ('aab', 2, 1, '2010-03-29 14:44'),
   ('aac', 3, 1, '2010-03-29 14:44'),
   ('aad', 4, 1, '2010-03-29 14:44'),
   ('aae', 5, 100, '2010-03-29 14:44'),
   ('aaf', 6, 1, '2010-03-29 14:44'),
   ('aag', 7, 1, '2010-03-29 14:44'),
   ('aah', 8, 1, '2010-03-29 14:44');

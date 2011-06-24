drop database if exists issue_1052;
create database issue_1052;
use issue_1052;
CREATE TABLE `t` (
  `opt_id` int(10) NOT NULL auto_increment,
  `value` text collate utf8_unicode_ci NOT NULL,
  `option` varchar(250) collate utf8_unicode_ci NOT NULL,
  `desc` varchar(300) collate utf8_unicode_ci NOT NULL,
  PRIMARY KEY  (`opt_id`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8;
insert into issue_1052.t values (null, 'val', 'opt', 'something');
set session sql_log_bin=0;
insert into issue_1052.t values (null, '', 'opt2', 'something else');

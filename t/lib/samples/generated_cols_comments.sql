CREATE TABLE `t1` (
  `id` int(11) unsigned NOT NULL AUTO_INCREMENT COMMENT 'The unique id of the audit record.',
  `source` enum('val1','val2') NOT NULL COMMENT 'Transaction originator',
  `tso_id` int(11) unsigned NOT NULL DEFAULT '0' COMMENT 'An internally generated transaction.',
  PRIMARY KEY (`id`),
) ENGINE=InnoDB DEFAULT CHARSET=latin1 COMMENT='some comment here generated'

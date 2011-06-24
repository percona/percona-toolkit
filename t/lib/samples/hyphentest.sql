CREATE TABLE `instrument_relation` (
  `pfk-source_instrument_id` int(10) unsigned NOT NULL,
  `pfk-related_instrument_id` int(10) unsigned NOT NULL,
  `sort_order` int(11) NOT NULL,
  PRIMARY KEY  (`pfk-source_instrument_id`,`pfk-related_instrument_id`),
  KEY `sort_order` (`sort_order`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1 COLLATE=latin1_german1_ci

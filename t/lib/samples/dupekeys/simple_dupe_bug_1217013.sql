CREATE TABLE `domains` (
  `id` bigint(20) NOT NULL,
  `domain` varchar(175) COLLATE utf8_bin NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `domain` (`domain`),
  UNIQUE KEY `unique_key_domain` (`domain`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_bin

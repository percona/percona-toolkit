DROP DATABASE IF EXISTS `test`;
CREATE DATABASE test;
USE test;

CREATE TABLE `users` (
  `id` int(10) unsigned NOT NULL,
  `username` varchar(255) NOT NULL,
  `full_name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `is_verified` tinyint(1) NOT NULL DEFAULT '0',
  `is_private` tinyint(1) NOT NULL DEFAULT '0',
  `profile_pic_url` varchar(255) DEFAULT NULL,
  `follower_count` int(11) NOT NULL DEFAULT '0',
  `following_count` int(11) NOT NULL DEFAULT '0',
  `media_count` int(11) NOT NULL DEFAULT '0',
  `biography` varchar(512) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `user_active` tinyint(1) NOT NULL DEFAULT '1',
  PRIMARY KEY (`id`),
  KEY `username` (`username`),
  KEY `follower_count` (`follower_count`),
  KEY `following_count` (`following_count`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE `user_comments` (
  `id_user_comments` int(11) NOT NULL AUTO_INCREMENT,
  `msg` varchar(255) DEFAULT NULL,
  `user_id` int(10) unsigned DEFAULT NULL,
  PRIMARY KEY (`id_user_comments`),
  KEY `fk1_idx` (`user_id`),
  CONSTRAINT `fk1` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE NO ACTION ON UPDATE NO ACTION
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=latin1;


INSERT INTO `test`.`users` (`id`, `username`, `full_name`, `is_verified`, `is_private`, `profile_pic_url`,
`follower_count`, `following_count`, `media_count`, `biography`, `user_active`)
VALUES
(1, "zappb", "zapp brannigan", 1, 1, "https://pbs.twimg.com/profile_images/447660347273408512/NdZEGKvr.jpeg", 0, 0, 0, "", 1);
 
INSERT INTO `test`.`user_comments` (`id_user_comments`, `msg`, `user_id`)
VALUES
(1, "I am the man with no name. Zapp Brannigan, at your service.", 1);

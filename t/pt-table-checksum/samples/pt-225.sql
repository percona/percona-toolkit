DROP DATABASE IF EXISTS test;
CREATE DATABASE test;

USE test;

CREATE TABLE `sbtest1` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `k` int(11) NOT NULL DEFAULT '0',
  `c` char(120) NOT NULL DEFAULT '',
  `pad` char(60) NOT NULL DEFAULT '',
  `json_test_v` json GENERATED ALWAYS AS (json_array(`k`,`c`,`pad`)) VIRTUAL,
  `json_test_s` json GENERATED ALWAYS AS (json_array(`k`,`c`,`pad`)) STORED,
  `json_test_index` varchar(255) GENERATED ALWAYS AS (json_array(`k`,`c`,`pad`)) STORED,
  PRIMARY KEY (`id`),
  KEY `k_1` (`k`),
  KEY `json_test_index` (`json_test_index`)
) ENGINE=InnoDB AUTO_INCREMENT=1001 DEFAULT CHARSET=latin1 COMPRESSION='lz4';


/*!40000 ALTER TABLE `sbtest1` DISABLE KEYS */;
INSERT INTO `sbtest1` (`id`, `k`, `c`, `pad`) VALUES 
(01,583532949,'at non eaque sint velit enim facilis quisquam nam quaerat.','impedit quae hic possimus ullam est eos totam qui.'),
(02,583532949,'eos exercitationem quisquam saepe totam dolore consequatur.','sit commodi consequatur neque qui.'),
(03,1342458479,'et quia sunt eum eveniet non eum nobis quia est mollitia.','corrupti minima et quibusdam.'),
(04,280366509,'ab minima laudantium!','est sed autem quia nobis suscipit pariatur modi!'),
(05,1801160058,'perspiciatis tenetur minima accusantium consequatur in et.','rerum quo molestiae voluptates harum aspernatur sunt.'),
(06,914091476,'quas aut nostrum a.','harum tempora adipisci et et.'),
(07,1022430181,'qui voluptates inventore voluptatem voluptas numquam blanditiis corporis illum doloremque aut!','dicta neque laboriosam voluptatibus.'),
(08,165910161,'voluptas molestiae harum quis quod.','voluptatem deleniti dolor blanditiis est earum.'),
(09,1255569388,'consequuntur nihil non veniam et possimus sunt.','est est possimus recusandae ab.'),
(10,1375471152,'doloribus quasi quasi eum hic et laborum autem laudantium saepe veritatis.','enim earum et placeat animi ut.'),
(11,1705409249,'eveniet recusandae expedita est consectetur ut laudantium temporibus.','et asperiores porro id sunt totam maiores eum quidem.'),
(12,2003588754,'debitis molestias voluptatibus quia.','sint est voluptatem nihil et.'),
(13,1714682759,'voluptas officiis culpa quaerat sit quis.','vitae omnis repellat rerum consectetur ex.'),
(14,1898674299,'et est quibusdam!','aut est labore.'),
(15,1698116023,'similique nisi quisquam pariatur minus repudiandae ducimus.','eveniet rem nihil voluptatibus voluptatem non.'),
(16,1310715836,'expedita ipsum aut veniam!','incidunt at officia nisi.'),
(17,472875023,'numquam et quaerat voluptatibus.','commodi natus consequatur reiciendis adipisci ut.'),
(18,1153628287,'aut quam quia vel molestiae qui.','eos voluptas quod doloremque!'),
(19,525456967,'dignissimos quibusdam aut et.','laborum reprehenderit eius consequatur qui.'),
(20,1396416465,'aperiam sint et.','fugiat neque impedit cumque soluta.'),
(21,1640670520,'nisi repellendus et velit ab.','incidunt quo eligendi.');

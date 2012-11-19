drop database if exists test;
create database test;
use test;

create table t (
  id  int auto_increment primary key,
  c   varchar(16) not null
) engine=innodb;

INSERT INTO `t` VALUES (1,'a'),(4,'b'),(7,'c'),(10,'d'),(13,'e'),(16,'f'),(19,'g'),(22,'h'),(25,'i'),(28,'j'),(31,'k'),(34,'l'),(37,'m'),(40,'n'),(43,'o'),(46,'p'),(49,'q'),(52,'r'),(55,'s'),(58,'t'),(61,'u'),(64,'v'),(67,'w'),(70,'x'),(73,'y'),(76,'z');

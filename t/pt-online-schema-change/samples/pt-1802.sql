CREATE TABLE `joinit` (
`i` int(11) NOT NULL AUTO_INCREMENT,
`s` varchar(64) DEFAULT NULL,
`t` time NOT NULL,
`g` int(11) NOT NULL,
`j` int(11) NOT NULL DEFAULT 1,
PRIMARY KEY (`i`))
ENGINE=InnoDB;
ALTER TABLE joinit ADD FOREIGN KEY i_fk (j) REFERENCES joinit (i) ON UPDATE cascade ON DELETE restrict;

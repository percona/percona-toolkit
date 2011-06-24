DROP DATABASE IF EXISTS issue_644;
CREATE DATABASE issue_644;
USE issue_644;
CREATE TABLE `t` (
  `legacy` varchar(255) default NULL,
  `new_one` varchar(255) default NULL,
  UNIQUE KEY `idx` (`legacy`)
) ENGINE=InnoDB;

INSERT INTO issue_644.t VALUES
('0611743165-2519-n-greenview-ave', '14293130030000'),
('0611743165-2520-n-greenview-ave', '14293130030001'),
('0611743165-2521-n-greenview-ave', '14293130030002'),  -- first boundary
('0611743165-3001-z-greenview-ave', '14293130030003'),
('0611743165-2520-z-greenview-ave', '14293130030004'),
('601940318', '14334230481014'),  -- leads back to first boundary
('600000500', '14334230481015'),
('600005000', '14334230481016'),
('601940320', '14334230481017');  -- never reached

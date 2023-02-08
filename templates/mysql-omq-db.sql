create user 'omq'@'%' identified by 'omq';
grant super on *.* to 'omq'@'%';
create user 'omq'@'localhost' identified by 'omq';
grant super on *.* to 'omq'@'localhost';

create database omq character set 'utf8';
grant all on omq.* to 'omq'@'%';
grant all on omq.* to 'omq'@'localhost';

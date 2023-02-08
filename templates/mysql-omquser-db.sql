create user 'omquser'@'%' identified by 'omquser';
grant super on *.* to 'omquser'@'%';
create user 'omquser'@'localhost' identified by 'omquser';
grant super on *.* to 'omquser'@'localhost';

create database omquser character set 'utf8';
grant all on omquser.* to 'omquser'@'%';
grant all on omquser.* to 'omquser'@'localhost';

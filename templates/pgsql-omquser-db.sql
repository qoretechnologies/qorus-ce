create database omquser encoding = 'utf8';
\connect omquser;
create tablespace omquser_data location '/opt/pgsql/tablespaces/omquser_data';
create tablespace omquser_index location '/opt/pgsql/tablespaces/omquser_index';
create user omquser password 'omquser';
grant create, connect, temp on database omquser to omquser;
grant create on tablespace omquser_data to omquser;
grant create on tablespace omquser_index to omquser;
grant select on all tables in schema pg_catalog to omquser;

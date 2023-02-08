create database omq encoding = 'utf8';
\connect omq;
create tablespace omq_data location '/opt/pgsql/tablespaces/omq_data';
create tablespace omq_index location '/opt/pgsql/tablespaces/omq_index';
create user omq password 'omq';
grant create, connect, temp on database omq to omq;
grant create on tablespace omq_data to omq;
grant create on tablespace omq_index to omq;
grant select on all tables in schema pg_catalog to omq;

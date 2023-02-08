create tablespace omquser_data
        datafile '/opt/oradata/XBOX_MASTER/datafile/omquser_data01.dbf' size 128M reuse
	autoextend on next 64M
        default storage (initial 1M next 1M minextents 1 maxextents 1000
        pctincrease 0);

create tablespace omquser_index
        datafile '/opt/oradata/XBOX_MASTER/datafile/omquser_index01.dbf' size 64M reuse
	autoextend on next 32M
        default storage (initial 500k next 500k minextents 1 maxextents 1000
        pctincrease 0);

create user omquser identified by omquser default tablespace omquser_data temporary tablespace temp;

-- WARNING: It's not recommended to use "unlimited tablespace" in real environments; allocate specific tablespace permissions as needed to DB users
grant create session, create procedure, create sequence, create table, create trigger, create type, create view, create synonym, unlimited tablespace to omquser;

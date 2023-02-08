
create tablespace omq_data
        datafile '/opt/oradata/XBOX_MASTER/datafile/omq_data01.dbf' size 512M reuse
	autoextend on next 256M
        default storage (initial 1M next 1M minextents 1 maxextents 1000
        pctincrease 0);

create tablespace omq_index
        datafile '/opt/oradata/XBOX_MASTER/datafile/omq_index01.dbf' size 256M reuse
	autoextend on next 128M
        default storage (initial 1M next 1M minextents 1 maxextents 1000
        pctincrease 0);

create user omq identified by omq default tablespace omq_data temporary tablespace temp;

-- WARNING: It's not recommended to use "unlimited tablespace" in real environments; allocate specific tablespace permissions as needed to DB users
grant create session, create procedure, create sequence, create table, create trigger, create type, create view, unlimited tablespace to omq;

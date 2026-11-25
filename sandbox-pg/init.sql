CREATE DATABASE pagila;
CREATE DATABASE pt_test;

\c pagila
\ir data/pagila/pagila-schema.sql
\ir data/pagila/pagila-data.sql

\c pt_test
CREATE TABLE t1 (id serial PRIMARY KEY, payload text);
INSERT INTO t1 (payload) SELECT 'row ' || g FROM generate_series(1, 100) g;

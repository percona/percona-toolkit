DROP DATABASE IF EXISTS float_precision;
CREATE DATABASE float_precision;
USE float_precision;
CREATE TABLE t (
  a float not null primary key,
  b double
);

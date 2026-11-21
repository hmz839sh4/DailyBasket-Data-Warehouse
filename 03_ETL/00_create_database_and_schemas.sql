-- Creates the dailybasket_dw database and its staging, warehouse and reporting schemas.

DROP DATABASE IF EXISTS dailybasket_dw;
CREATE DATABASE dailybasket_dw;

\c dailybasket_dw

CREATE SCHEMA IF NOT EXISTS project_staging;
CREATE SCHEMA IF NOT EXISTS project_dw;
CREATE SCHEMA IF NOT EXISTS project_reporting;

SELECT schema_name
FROM information_schema.schemata
WHERE schema_name LIKE 'project_%'
ORDER BY schema_name;

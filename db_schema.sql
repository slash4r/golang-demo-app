CREATE DATABASE db;
\c db
CREATE TABLE IF NOT EXISTS videos (
  id VARCHAR(255) NOT NULL,
  title VARCHAR(255) NOT NULL
);
# new code reloaded
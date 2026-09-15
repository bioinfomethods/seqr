CREATE DATABASE seqrdb;
CREATE DATABASE reference_data_db;
-- Keycloak stores its realms, clients and users here, isolated from seqrdb so that
-- dumping or rebuilding either is independent of the other.
--
-- The postgres image runs this file ONLY when initialising an empty data directory, so
-- it does not help a ./data/postgres that predates Keycloak. The keycloak-db-init
-- service in docker-compose.yml creates the database idempotently on every start and is
-- what actually guarantees it exists; this line just saves it a round trip on a fresh
-- volume. Keep the two in step.
CREATE DATABASE keycloak;

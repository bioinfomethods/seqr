-- NOTE: seqr_user is defined in users.xml, and ClickHouse's users_xml access
-- storage is read-only -- GRANT against it fails with ACCESS_STORAGE_READONLY.
-- The named-collection privileges this file used to grant are therefore declared
-- directly on the user in users.xml (named_collection_control /
-- show_named_collections / show_named_collections_secrets).
SELECT 1;

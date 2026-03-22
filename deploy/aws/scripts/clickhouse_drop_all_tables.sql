-- Drop all seqr tables from ClickHouse (without dropping/recreating the database).
-- Run via: clickhouse client --host localhost --port 8169 --user default --multiquery < clickhouse_drop_all_tables.sql
--
-- Order: materialized views → dictionaries → join tables → clinvar → entries →
--        project_gt_stats → gt_stats → transcripts → key_lookup → annotations → other

-- 1. Materialized views (depend on source/target tables)
DROP TABLE IF EXISTS seqr.`GRCh37/SNV_INDEL/clinvar_all_variants_to_clinvar_mv` SYNC;
DROP TABLE IF EXISTS seqr.`GRCh38/SNV_INDEL/clinvar_all_variants_to_clinvar_mv` SYNC;
DROP TABLE IF EXISTS seqr.`GRCh38/MITO/clinvar_all_variants_to_clinvar_mv` SYNC;
DROP TABLE IF EXISTS seqr.`GRCh38/SNV_INDEL/entries_to_project_gt_stats_mv` SYNC;
DROP TABLE IF EXISTS seqr.`GRCh38/MITO/entries_to_project_gt_stats_mv` SYNC;
DROP TABLE IF EXISTS seqr.`GRCh38/SV/entries_to_project_gt_stats_mv` SYNC;
DROP TABLE IF EXISTS seqr.`GRCh38/SNV_INDEL/project_gt_stats_to_gt_stats_mv` SYNC;
DROP TABLE IF EXISTS seqr.`GRCh38/MITO/project_gt_stats_to_gt_stats_mv` SYNC;
DROP TABLE IF EXISTS seqr.`GRCh38/SV/project_gt_stats_to_gt_stats_mv` SYNC;

-- 2. Dictionaries
DROP DICTIONARY IF EXISTS seqr.`GRCh38/SNV_INDEL/gt_stats_dict`;
DROP DICTIONARY IF EXISTS seqr.`GRCh38/MITO/gt_stats_dict`;
DROP DICTIONARY IF EXISTS seqr.`GRCh38/SV/gt_stats_dict`;
DROP DICTIONARY IF EXISTS seqr.`GRCh38/SNV_INDEL/project_partitions_dict`;
DROP DICTIONARY IF EXISTS seqr.seqrdb_affected_status_dict;

-- 3. Join tables (clinvar joins depend on entries)
DROP TABLE IF EXISTS seqr.`GRCh37/SNV_INDEL/clinvar` SYNC;
DROP TABLE IF EXISTS seqr.`GRCh38/SNV_INDEL/clinvar` SYNC;
DROP TABLE IF EXISTS seqr.`GRCh38/MITO/clinvar` SYNC;

-- 4. Clinvar all_variants and seqr_variants
DROP TABLE IF EXISTS seqr.`GRCh37/SNV_INDEL/clinvar_all_variants` SYNC;
DROP TABLE IF EXISTS seqr.`GRCh38/SNV_INDEL/clinvar_all_variants` SYNC;
DROP TABLE IF EXISTS seqr.`GRCh38/MITO/clinvar_all_variants` SYNC;
DROP TABLE IF EXISTS seqr.`GRCh37/SNV_INDEL/reference_data/clinvar/seqr_variants` SYNC;
DROP TABLE IF EXISTS seqr.`GRCh38/SNV_INDEL/reference_data/clinvar/seqr_variants` SYNC;
DROP TABLE IF EXISTS seqr.`GRCh38/MITO/reference_data/clinvar/seqr_variants` SYNC;
DROP TABLE IF EXISTS seqr.`GRCh37/SNV_INDEL/reference_data/clinvar/all_variants` SYNC;
DROP TABLE IF EXISTS seqr.`GRCh38/SNV_INDEL/reference_data/clinvar/all_variants` SYNC;
DROP TABLE IF EXISTS seqr.`GRCh38/MITO/reference_data/clinvar/all_variants` SYNC;

-- 5. Entries
DROP TABLE IF EXISTS seqr.`GRCh37/SNV_INDEL/entries` SYNC;
DROP TABLE IF EXISTS seqr.`GRCh38/SNV_INDEL/entries` SYNC;
DROP TABLE IF EXISTS seqr.`GRCh38/MITO/entries` SYNC;
DROP TABLE IF EXISTS seqr.`GRCh38/SV/entries` SYNC;
DROP TABLE IF EXISTS seqr.`GRCh38/GCNV/entries` SYNC;

-- 6. Project GT stats
DROP TABLE IF EXISTS seqr.`GRCh37/SNV_INDEL/project_gt_stats` SYNC;
DROP TABLE IF EXISTS seqr.`GRCh38/SNV_INDEL/project_gt_stats` SYNC;
DROP TABLE IF EXISTS seqr.`GRCh38/MITO/project_gt_stats` SYNC;
DROP TABLE IF EXISTS seqr.`GRCh38/SV/project_gt_stats` SYNC;

-- 7. GT stats
DROP TABLE IF EXISTS seqr.`GRCh37/SNV_INDEL/gt_stats` SYNC;
DROP TABLE IF EXISTS seqr.`GRCh38/SNV_INDEL/gt_stats` SYNC;
DROP TABLE IF EXISTS seqr.`GRCh38/MITO/gt_stats` SYNC;
DROP TABLE IF EXISTS seqr.`GRCh38/SV/gt_stats` SYNC;

-- 8. Transcripts
DROP TABLE IF EXISTS seqr.`GRCh37/SNV_INDEL/transcripts` SYNC;
DROP TABLE IF EXISTS seqr.`GRCh38/SNV_INDEL/transcripts` SYNC;

-- 9. Key lookups
DROP TABLE IF EXISTS seqr.`GRCh37/SNV_INDEL/key_lookup` SYNC;
DROP TABLE IF EXISTS seqr.`GRCh38/SNV_INDEL/key_lookup` SYNC;
DROP TABLE IF EXISTS seqr.`GRCh38/MITO/key_lookup` SYNC;
DROP TABLE IF EXISTS seqr.`GRCh38/SV/key_lookup` SYNC;
DROP TABLE IF EXISTS seqr.`GRCh38/GCNV/key_lookup` SYNC;

-- 10. Annotations (disk then memory)
DROP TABLE IF EXISTS seqr.`GRCh37/SNV_INDEL/annotations_disk` SYNC;
DROP TABLE IF EXISTS seqr.`GRCh37/SNV_INDEL/annotations_memory` SYNC;
DROP TABLE IF EXISTS seqr.`GRCh38/SNV_INDEL/annotations_disk` SYNC;
DROP TABLE IF EXISTS seqr.`GRCh38/SNV_INDEL/annotations_memory` SYNC;
DROP TABLE IF EXISTS seqr.`GRCh38/MITO/annotations_disk` SYNC;
DROP TABLE IF EXISTS seqr.`GRCh38/MITO/annotations_memory` SYNC;
DROP TABLE IF EXISTS seqr.`GRCh38/SV/annotations_disk` SYNC;
DROP TABLE IF EXISTS seqr.`GRCh38/SV/annotations_memory` SYNC;
DROP TABLE IF EXISTS seqr.`GRCh38/GCNV/annotations_disk` SYNC;
DROP TABLE IF EXISTS seqr.`GRCh38/GCNV/annotations_memory` SYNC;

-- 11. Project partitions
DROP TABLE IF EXISTS seqr.`GRCh38/SNV_INDEL/project_partitions` SYNC;

-- 12. Django migrations (so migrate will re-create everything cleanly)
DROP TABLE IF EXISTS seqr.django_migrations SYNC;

-- 13. Any remaining tables with known names
DROP TABLE IF EXISTS seqr.seqrdb_affected_status_dict SYNC;

SELECT 'All seqr tables dropped successfully.' AS status;

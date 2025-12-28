# MCRI Seqr Clickhouse Conversion

Seqr is a rare disease analysis tool that supports searching through large scale
genomic variant data sets to find causative rare disease variants.

Seqr has historically been hosted on an ElasticSearch backend, however this
is every expensive to run and does not support some kinds of required searches
well.

Therefore a new back end has been developed based on Clickhouse. Currently,
the code supports both Clickhouse AND ElasticSearch.

This current project is to MIGRATE our current install, database and setup
from using ElasticSearch to Clickhouse. There are many unknown aspects
that need to be defined and understood before we can perform this migration.
For example, there is a significant store of data sitting in ElasticSearch,
and we will desire to migrate this data in some fashion to Clickhouse.

The primary focus of current exploration is to develop a plan by which 
we can migrate out existing instance of Seqr from using ElasticSearch
to Clickhouse.

---

## Migration Plan Overview

### Phase 1: Infrastructure Setup
Deploy Clickhouse infrastructure alongside existing ElasticSearch:
- Add Clickhouse service to docker-compose.yml
- Configure Clickhouse server settings (users, memory, storage)
- Set up health checks and networking
- Create environment variables for backend configuration
- Start Clickhouse container and verify connectivity

### Phase 2: Schema Initialization
Initialize Clickhouse database schema:
- Run Django migrations to create all Clickhouse tables
- Verify table creation (Annotations, Entries, Transcripts, etc.)
- Set up PostgreSQL named collection for dictionary integration
- Create and verify dictionaries (sex, affected status)
- Validate materialized views are functioning

### Phase 3: Schema Analysis & Mapping
Understand data structures in both systems:
- Document ElasticSearch index structure and naming conventions
- Document Clickhouse table structure and relationships
- Analyze field mappings between ES documents and CH tables
- Identify complex transformations (nested fields, genotypes, transcripts)
- Document key generation strategy for variant identification
- Map ES aggregations to CH query patterns

### Phase 4: Backend Management Analysis
Understand how the application switches between backends:
- Review search API implementation and routing logic
- Identify all search entry points in the codebase
- Document the `@clickhouse_only` decorator usage
- Understand `query_variants()` backend selection mechanism
- Map all search features to backend implementations
- Identify features that require Clickhouse-specific code

### Phase 5: Migration Tool Development
Build tools to migrate data from ElasticSearch to Clickhouse:
- Create ES export script to extract variant data
- Implement transformation logic for data format conversion
- Build bulk import script for Clickhouse insertion
- Develop validation script to compare ES vs CH data
- Create rollback procedures for failed migrations
- Implement progress tracking and error handling

### Phase 6: Full Data Migration
Migrate all production data:
- Execute migration in batches by project
- Monitor progress and handle errors
- Validate each batch after migration
- Maintain ElasticSearch as fallback during migration
- Document any data discrepancies


---

## Migration Checklist

### Phase 1: Infrastructure Setup
- [x] Add Clickhouse service to docker-compose.yml
- [x] Create clickhouse_config directory and configuration files
- [x] Create .env file with Clickhouse credentials
- [ ] Start Clickhouse container
- [ ] Verify Clickhouse connectivity
- [ ] Verify health checks pass

### Phase 2: Schema Initialization
- [ ] Run Django migrations for Clickhouse
- [ ] Verify all tables created successfully
- [ ] Create PostgreSQL named collection
- [ ] Verify dictionaries are working
- [ ] Check materialized views are created
- [ ] Document table structure

### Phase 3: Schema Analysis & Mapping
- [ ] Document ES index naming convention
- [ ] List all ES indices and their sizes
- [ ] Document ES document structure
- [ ] Document CH table relationships
- [ ] Map ES fields to CH columns
- [ ] Identify complex transformation requirements
- [ ] Document key generation strategy
- [ ] Create schema mapping reference document

### Phase 4: Backend Management Analysis
- [ ] Review seqr/utils/search/utils.py
- [ ] Review seqr/utils/search/elasticsearch/es_utils.py
- [ ] Review seqr/utils/search/elasticsearch/constants.py
- [ ] Document backend selection mechanism
- [ ] List all search API endpoints
- [ ] Identify Clickhouse-only features
- [ ] Document feature parity between backends

### Phase 5: Migration Tool Development
- [ ] Create ES export management command
- [ ] Implement data transformation logic
- [ ] Create CH bulk import functionality
- [ ] Build validation script
- [ ] Implement error handling and logging
- [ ] Create rollback procedures
- [ ] Test tools on sample data

### Phase 6: Full Data Migration
- [ ] Create migration execution plan
- [ ] Migrate GRCh38 SNV/INDEL data
- [ ] Migrate GRCh37 SNV/INDEL data
- [ ] Migrate MITO data
- [ ] Migrate SV data
- [ ] Migrate GCNV data
- [ ] Validate each dataset
- [ ] Document migration statistics

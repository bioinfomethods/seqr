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
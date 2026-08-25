# MCRI Seqr Clickhouse Conversion

Seqr is a rare disease analysis tool that supports searching through large scale
genomic variant data sets to find causative rare disease variants.

Seqr has historically been hosted on an ElasticSearch backend, however this
is every expensive to run and does not support some kinds of required searches
well.

Therefore a new back end has been developed based on Clickhouse. Currently,
the code supports both Clickhouse AND ElasticSearch.

We have so far worked to establish a local working instance of Seqr running
using the Clickhouse back end using the local development docker-compose
setup.

We then worked to move this locally working setup to a AWS deployed
infrastructure (configured in `deploy/aws`). 

The current context:

- the AWS setup works, but does not cleanly re-create from zero via terraform.
- we are working to ensure a clean, start-from-zero process work smoothly

## ClickHouse Migrations

ClickHouse migrations use a separate database connection. When running
migrations for the `clickhouse_search` app, you **must** specify the database:

```bash
python manage.py migrate clickhouse_search --database clickhouse_writer
```

Similarly for showmigrations:

```bash
python manage.py showmigrations clickhouse_search --database clickhouse_writer
```

Without `--database clickhouse_writer`, Django will use the default (PostgreSQL)
database router and the migrations won't actually execute against ClickHouse.



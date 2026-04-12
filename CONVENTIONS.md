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
infrastructure (configured in `deploy/aws`). That work has reached a milestone
point where we now need to switch back to local development.

We are now working on a feature to support OIDC based login via Keycloak. This
work is detailed in `plans/OIDC.md`. Read this file and ask to see it if you
do not have access.

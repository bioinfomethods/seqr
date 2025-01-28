# seqr

![Unit Tests](https://github.com/bioinfomethods/seqr/actions/workflows/unit-tests.yml/badge.svg)

seqr is a web-based tool for rare disease genomics.

This is a fork of [https://github.com/macarthur-lab/seqr](https://github.com/macarthur-lab/seqr) with some customisations
made for MCRI.  This instance is internally hosted.  `mcri/master` branch is the mainline branch at MCRI.

MCRI specific deployment instructions can be found [here](https://github.com/bioinfomethods/seqr/tree/mcri/master/mcri_deploy).

## Technical Overview

seqr consists of the following components:
- postgres - SQL database used by seqr to store project metadata and user-generated content such as variant notes, etc.
- elasticsearch - NoSQL database used to store variant callsets.
- redis - in-memory cache used to speed up request handling.
- seqr - the main client-server application built using react.js, python and django.
- pipeline-runner - optional container for running hail pipelines to annotate and load new datasets into elasticsearch. If seqr is hosted on google cloud (GKE or GCE), Dataproc spark clusters can be used instead.
- kibana - optional dashboard and visual interface for elasticsearch.

## Install

The seqr production instance runs on Google Kubernetes Engine (GKE) and data is loaded using Google Dataproc Spark clusters. 

On-prem installs using the elasticsearch backend can be created using docker-compose:
 **[Local installs using docker-compose](deploy/LOCAL_INSTALL.md)**

On-prem installs using the `hail` backend can be created using **[helm](deploy/LOCAL_INSTALL_HELM.md)**

To help you decide which backend is best suited for your needs, please refer to the discussion post [announcing the `hail` backend](https://github.com/broadinstitute/seqr/discussions/4531).

To set up seqr for local development, see instructions **[here](deploy/LOCAL_DEVELOPMENT_INSTALL.md)**  

## Updating / Migrating an older seqr Instance	

For notes on how to update an older instance, see  	

[Update/Migration Instructions](deploy/MIGRATE.md)

## Contributing to seqr

(Note: section inspired by, and some text copied from, [GATK](https://github.com/broadinstitute/gatk#contribute))

We welcome all contributions to seqr. 
Code should be contributed via GitHub pull requests against the main seqr repository.

If you’d like to report a bug but don’t have time to fix it, you can submit a
[GitHub issue](https://github.com/broadinstitute/seqr/issues/new?assignees=&labels=bug&template=bug_report.md&title=)

For larger features, feel free to discuss your ideas or approach in our 
[discussion forum](https://github.com/broadinstitute/seqr/discussions)

To contribute code:

- Submit a GitHub pull request against the master branch.

- Break your work into small, single-purpose patches whenever possible. 
However, do not break apart features to the point that they are not functional 
(i.e. updates that require changes to both front end and backend code should be submitted as a single change)

- For larger features, add a detailed description to the pull request to explain the changes and your approach

- Make sure that your code passes all our tests and style linting

- Add unit tests for all new python code you've written

We tend to do fairly close readings of pull requests, and you may get a lot of comments.

Thank you for getting involved!

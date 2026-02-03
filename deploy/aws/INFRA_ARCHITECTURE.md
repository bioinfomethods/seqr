# Seqr AWS Infrastructure

This directory contains OpenTofu / Terraform infrastruture for deploying
seqr in an AWS environment.

This architecture is designed to support a mid-scale deployment, where
the back end is self contained on a single node.

The following sections describe the setup and components.

## Environments

The architecture supports dev, test, and prod environments. All resources are
according to the following structure:

```
<prefix>-seqr-<environment>-<component>
```

This applies to intrinsic names (such as buckets) as well as `Name` tags that should be
applied to each component.

## Configuration

All configuration is controlled by a YAML file in the `config` directory that is
named according to the environment, eg:


```
config/dev.yaml
```

## Tagging

All resources are tagged with a set of default tags that are static for each deployment:

- `Environment`
- `CostCentre`

This set is configurable in the YAML file.  Each resource also has a `Name` tag where that is
appropriate / allowed.

## Terraform State

State is stored in an S3 bucket that is pre-configured and named according to the scheme:

```
<prefix>-seqr-<environment>-terraform-state
```

## Networking

- The application runs in the default VPC for the account
- While the VPC is a public VPC, security groups prevent all public access to the components in the VPC
- Access is provisioned via a bastian host that is accessible only through an SSH tunnel

## Components

The architecture consists of the following components:

## Application Load Balancer (ALB)

- An ALB supports connections to Django running in the ECS container

## Bastian host

- a host that facilitates access by supporting an SSH tunnel to the ALB

## Postgres Aurora Database

- database configured with all required back end state

## Elastic Container Registry

- A container registry containing images to be deployed for Django container and Clickhouse back ends

## Clickhouse Database

- An EC2 instance that runs the Clickhouse database. This instance is launched using a preconfigured image,
  however the image itself simply runs Clickhouse in a container, which is a standard Clickhouse database
  image from dockerhub

## Django Container

- An ECS service that runs Django in a container image named seqr-web that is stored in ECR
- The Django container connects to the Aurora database and is configured with connection details via environment variables
- The Django container connects to the Clickhouse database and is configured with connection details via environment variables



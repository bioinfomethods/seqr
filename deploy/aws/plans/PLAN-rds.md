# Plan: Replace Aurora with RDS PostgreSQL

**Status**: Not started. Dev only, no data, so no migration is needed.

## Decisions (confirmed)
- Rename `modules/aurora` → `modules/postgres`, and rename `aurora_*` vars/outputs → `db_*`
- `db.t4g.small`, Multi-AZ off (`db_multi_az` var), 20→100 GB gp3 encrypted, engine `"17.7"`

## Steps
1. Create `modules/postgres/` with main.tf, variables.tf and outputs.tf. Replace the cluster and cluster instance with a single `aws_db_instance`, and keep the SG and subnet group. Add the `allocated_storage`, `max_allocated_storage` and `multi_az` vars. Use a static `final_snapshot_identifier` (no `timestamp()`). Delete `modules/aurora/`.
2. Module outputs: `endpoint` (must be `.address`, NOT `.endpoint`, which returns host:port), `port`, `database_name`, `master_username`, `security_group_id`, `instance_id`. No reader endpoint.
3. Rename the root `variables.tf` vars from `aurora_*` to `db_*`, and change the instance class default to `db.t4g.small`. Add the multi_az and storage vars.
4. Update the references in `main.tf` (module call + ClickHouse user_data), `fargate.tf` (POSTGRES_* env vars) and `outputs.tf`. Drop the reader endpoint output and add `sslmode=require` to the psql command.
5. Apply the same renames in `terraform-dev.tfvars.example`. The user must edit their real tfvars by hand.
6. Update `PLAN.md` and `INFRA_ARCHITECTURE.md` to say RDS instead of Aurora.

## After apply
- ClickHouse is replaced because its user_data changes. This is expected, and the data volume is preserved.
- Create `reference_data_db` manually from the bastion.
- Django migrations run against the empty DB.

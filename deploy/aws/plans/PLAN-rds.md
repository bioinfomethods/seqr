# Plan: Replace Aurora with RDS PostgreSQL

**Status**: In progress. Steps 1–5 done (code); step 6 (docs) next. Dev only, no data, so no migration is needed.

**WARNING**: Before `tofu plan`, edit the real tfvars by hand (see step 5). Until then it uses the `aurora_*` keys, so `db_master_password` is unset. Run `tofu init` before the first plan, because the module source changed to `./modules/postgres`.

## Decisions (confirmed)
- Rename `modules/aurora` → `modules/postgres`, and rename `aurora_*` vars/outputs → `db_*`
- `db.t4g.small`, Multi-AZ off (`db_multi_az` var), 20→100 GB gp3 encrypted, engine `"17.7"` (confirmed available in ap-southeast-2)
- Storage: `allocated_storage = 20` with autoscaling to `max_allocated_storage = 100`
- Recreate (no `moved` blocks). New names avoid create-before-destroy collisions: `…-postgres-sg`, `…-postgres-subnet-group`, identifier `…-postgres`
- Add `db_deletion_protection` var (default `false`)
- Final snapshot name: `${name_prefix}-postgres-final-snapshot` (static; a second destroy with snapshots enabled fails if it already exists)
- Module SG inputs (bastion, ClickHouse, ECS) are required, with plain `ingress` blocks (avoids unknown-value `for_each` failure on a fresh build)
- `aurora_reference_database_name` → `db_reference_database_name`
- Scripts: rename `LOCAL_AURORA_PORT` → `LOCAL_DB_PORT` (default 8168 unchanged)
- Update `PLAN-fargate.md` and `README.md` too (not just `PLAN.md` / `INFRA_ARCHITECTURE.md`)
- Module outputs: `instance_id` uses `.identifier` (`.id` returns the `db-XXXX` resource ID in provider v5)
- ClickHouse SSL: `start-clickhouse.sh` / docker-compose already use `PGSSLMODE=require`, so `rds.force_ssl=1` is fine; no AMI rebuild needed

## Steps
1. [x] Create `modules/postgres/` with main.tf, variables.tf and outputs.tf. Replace the cluster and cluster instance with a single `aws_db_instance`, and keep the SG and subnet group. Add the `allocated_storage`, `max_allocated_storage`, `multi_az` and `deletion_protection` vars. Use a static `final_snapshot_identifier` (no `timestamp()`). (commit 51e0ef1)
   - Deleting `modules/aurora/` is deferred to step 4, so `main.tf` never references a missing module.
2. [x] Module outputs: `endpoint` (must be `.address`, NOT `.endpoint`, which returns host:port), `port`, `database_name`, `master_username`, `security_group_id`, `instance_id`. No reader endpoint. (commit 51e0ef1)
3. [x] Rename the root `variables.tf` vars from `aurora_*` to `db_*`, and change the instance class default to `db.t4g.small`. Add the multi_az, storage and deletion_protection vars.
4. [x] Update the references in `main.tf` (module call + ClickHouse user_data + Aurora comments), `fargate.tf` (POSTGRES_* env vars + SG comments) and `outputs.tf`. Drop the reader endpoint output and add `sslmode=require` to the psql command. Delete `modules/aurora/` (`git rm -r deploy/aws/modules/aurora`).
   - Root outputs are now `db_endpoint`, `db_port`, `db_database_name`, `db_master_username`, `db_security_group_id`, `db_instance_id` and `db_psql_command`.
   - The module call also passes `allocated_storage`, `max_allocated_storage`, `multi_az` and `deletion_protection`.
   - 4b. [ ] Update `scripts/ssh-to-bastion.sh` (outputs `db_endpoint` / `db_port`, `LOCAL_DB_PORT`, labels) and `scripts/recreate-database.sh` (tfvars key `db_master_password`, `LOCAL_DB_PORT`, header comment).
5. [ ] Apply the same renames in `terraform-dev.tfvars.example` (instance class → `db.t4g.small`). The user must edit their real tfvars by hand: edit the symlink target `terraform-dev.tfvars` (not the `terraform.tfvars` symlink), rename `aurora_*` → `db_*`, and set or remove `db_instance_class` (currently overridden to `db.t3.medium`).
6. [ ] Update `PLAN.md`, `INFRA_ARCHITECTURE.md`, `PLAN-fargate.md` and `README.md` to say RDS instead of Aurora. `README_SIMON.md` is left alone.

## After apply
- ClickHouse is replaced because its user_data changes. This is expected, and the data volume is preserved.
- Create `reference_data_db` manually from the bastion.
- Django migrations run against the empty DB.

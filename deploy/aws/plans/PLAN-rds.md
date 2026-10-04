# Plan: Replace Aurora with RDS PostgreSQL

**Status** (2026-10-04, end of session): The infrastructure change is applied. RDS PostgreSQL is live, and ClickHouse was recreated and now points at `mcri-seqr-dev-postgres.cjcmke28sozw.ap-southeast-2.rds.amazonaws.com`. Steps 1–5 are done. Step 6 (docs) is partly done: only `PLAN-fargate.md` remains. Post-apply verification is NOT yet done (see "After apply" and "Session handoff" below). Dev only, no data, so no migration is needed.

**NOTE**: `tofu init` is required after a fresh clone, because the module source is `./modules/postgres` and `modules/aurora` was removed.

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
3. [x] Rename the root `variables.tf` vars from `aurora_*` to `db_*`, and change the instance class default to `db.t4g.small`. Add the multi_az, storage and deletion_protection vars. (commit 527041b)
4. [x] Update the references in `main.tf` (module call + ClickHouse user_data + Aurora comments), `fargate.tf` (POSTGRES_* env vars + SG comments) and `outputs.tf`. Drop the reader endpoint output and add `sslmode=require` to the psql command. Delete `modules/aurora/` (`git rm -r deploy/aws/modules/aurora`).
   - Root outputs are now `db_endpoint`, `db_port`, `db_database_name`, `db_master_username`, `db_security_group_id`, `db_instance_id` and `db_psql_command`.
   - The module call also passes `allocated_storage`, `max_allocated_storage`, `multi_az` and `deletion_protection`.
   - (commit 894d37b; `modules/aurora` removed with `git rm`)
   - 4b. [x] Update `scripts/ssh-to-bastion.sh` (outputs `db_endpoint` / `db_port`, `LOCAL_DB_PORT`, labels) and `scripts/recreate-database.sh` (tfvars key `db_master_password`, `LOCAL_DB_PORT`, header comment). (commit b9d9ca3)
5. [x] Apply the same renames in `terraform-dev.tfvars.example` (instance class → `db.t4g.small`). The user must edit their real tfvars by hand: edit the symlink target `terraform-dev.tfvars` (not the `terraform.tfvars` symlink), rename `aurora_*` → `db_*`, and set or remove `db_instance_class` (currently overridden to `db.t3.medium`). (commit b9d9ca3)
6. [ ] Update `PLAN.md`, `INFRA_ARCHITECTURE.md`, `PLAN-fargate.md` and `README.md` to say RDS instead of Aurora. `README_SIMON.md` is left alone.
   - [x] `README.md`, `INFRA_ARCHITECTURE.md`, `PLAN.md` (commit 5e6dcd6). `PLAN.md` Phase 3 is kept as history with a "superseded" note.
   - [ ] `PLAN-fargate.md`: architecture diagram, env var table, "Dependencies" (`module.aurora` → `module.postgres`), "Resolved Issues" and "Open Questions" (Aurora password → DB password).

## After apply
- [x] ClickHouse replaced (user_data changed). The cloud-init log was checked: the data volume attached and was reused (not reformatted, so data was kept), the named collection got the RDS host, and `docker compose up` succeeded.
- [ ] Restart the bastion tunnel (`./scripts/ssh-to-bastion.sh`). The ClickHouse IP and DB endpoint both changed, so old tunnels point at stale targets.
- [ ] Verify ClickHouse is actually serving: `clickhouse client --host localhost --port 8169 --user default --query "SELECT version()"`
- [ ] Create `reference_data_db`: `./scripts/postgres_client.sh postgres -c "CREATE DATABASE reference_data_db;"`
- [ ] Confirm the ECS task started and Django migrations ran against the empty DB (CloudWatch log group `/ecs/mcri-seqr-dev-seqr-web`). Restart the service with `./scripts/deploy-seqr.sh` if it failed before `reference_data_db` existed.
- [ ] Verify ClickHouse → RDS end to end (SSL + credentials), after migrations: `clickhouse client --host localhost --port 8169 --user default --query "SELECT count() FROM postgresql(seqr_postgres_named_collection, table='django_migrations')"`
  - `seqrdb_*` dictionaries fail to load until migrations have populated RDS. This is expected.

## Session handoff (2026-10-04)

### Done this session (besides the steps above)
- Added `scripts/postgres_client.sh`, a psql client through the bastion tunnel (`LOCAL_DB_PORT`, default 8168, `sslmode=require`, password from tfvars `db_master_password` / `PGPASSWORD` / prompt), plus a README "Connecting to PostgreSQL" section. (commit 60394c6)
- The real tfvars (`terraform-dev.tfvars`) was edited by hand: `aurora_*` → `db_*`, and `db_instance_class = "db.t4g.small"`.

### Outstanding (next session)
1. Run the "After apply" verification checklist above.
2. Step 6: update `PLAN-fargate.md`.
3. `scripts/clickhouse_client.sh`: the proposed rewrite never applied. The file still has no shebang (it starts with a blank line) and hard-codes port 8169. Planned changes:
   - Add `#!/bin/bash` and `set -euo pipefail`.
   - Use `LOCAL_CLICKHOUSE_PORT` (default 8169), `CH_HOST` and `CH_USER`.
   - Add a tunnel check, pass `"$@"` through, and send the tip text to stderr.
4. `scripts/clickhouse_drop_all_tables.sql`: delete the old `-- Run via:` header line (the run command is now duplicated).
5. Optional: add a Packer provisioner to install `scripts/diagnose-clickhouse.sh` into `/home/ec2-user/clickhouse/scripts/` (takes effect only after an AMI rebuild).

### Gotchas / notes
- `diagnose-clickhouse.sh` is NOT on the ClickHouse instance. It only exists in the repo, and it is lost whenever the instance is replaced. To use it, copy it via the bastion, then run `sudo bash ~/diagnose-clickhouse.sh`:
  - `scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ~/.ssh/id_ed25519_mcri_aws -o "ProxyCommand=ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ~/.ssh/id_ed25519_mcri_aws -W %h:%p ec2-user@$(tofu output -raw bastion_public_ip)" scripts/diagnose-clickhouse.sh ec2-user@$(tofu output -raw clickhouse_private_ip):~/`
- The "Clickhouse started successfully" message in cloud-init only means `docker compose up -d` returned. It is not a health check.
- `/dev/nvme1n1 not found … Waiting (1/60)` in the cloud-init log is a harmless attach race.
- Root outputs were renamed (`db_endpoint`, `db_port`, …, `db_psql_command`). Any external notes or scripts that use `aurora_*` outputs are broken.
- RDS enforces SSL (`rds.force_ssl=1`). ClickHouse uses `PGSSLMODE=require`, psql/scripts use `sslmode=require`, and Django uses the default `prefer`.
- The RDS password must not contain `/`, `"`, `@` or spaces.
- The final snapshot identifier is static (`mcri-seqr-dev-postgres-final-snapshot`). With `db_skip_final_snapshot = false`, a second destroy fails if that snapshot still exists.

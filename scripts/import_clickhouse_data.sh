
# Needs to be done in uv environment /Users/simon.sadedin/work/tools/uv/environments/seqr-loading-pipelines/bin/python
pushd /Users/simon.sadedin/work/tools/seqr-loading-pipelines-clickhouse
PYTHONPATH=/Users/simon.sadedin/work/tools/seqr-loading-pipelines-clickhouse python v03_pipeline/bin/load_to_clickhouse.py  --reference-genome GRCh38 --dataset-type SNV_INDEL --run-id 20260120-183723-474796 --project-guids R0133_testclickhouse --family-guids F003848_f0002


cd /Users/simon.sadedin/work/tools/seqr-clickhouse
scp -r mk4:/misc/bioinf-ops/seqr-clickhouse-ingest/pipeline-data/GRCh38/SNV_INDEL/runs/20260120-183723-474796  /Users/simon.sadedin/work/tools/seqr-clickhouse/data/clickhouse-seqr-data/pipeline-data/GRCh38/SNV_INDEL/runs

# needs to be done in uv environment /Users/simon.sadedin/work/tools/uv/environments/seqr/bin/python
python manage.py register_clickhouse_dataset R0133_testclickhouse  WGS  SNV_INDEL 

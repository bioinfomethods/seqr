
echo
echo "Make sure you already ran the bastion port forward script ..."
echo
echo "Tip: To drop all tables, run:"
echo "  clickhouse client --host localhost --port 8169 --user default --multiquery < deploy/aws/scripts/clickhouse_drop_all_tables.sql"
echo

clickhouse client --host localhost --port 8169 --user default

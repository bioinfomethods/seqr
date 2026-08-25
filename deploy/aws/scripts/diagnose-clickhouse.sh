#!/bin/bash
# Diagnostic script for ClickHouse instance
# Run this ON the ClickHouse EC2 instance to identify why ClickHouse isn't running.
#
# Usage (from your local machine):
#   # Copy and run on the instance:
#   scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
#       -o "ProxyCommand=ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ~/.ssh/KEY -W %h:%p ec2-user@BASTION_IP" \
#       deploy/aws/scripts/diagnose-clickhouse.sh ec2-user@CLICKHOUSE_IP:~/
#   # Then SSH in and run: sudo ~/diagnose-clickhouse.sh
#
# Or run directly via the ssh-to-clickhouse.sh script and then:
#   sudo ~/diagnose-clickhouse.sh

set -o pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

ISSUES=()
WARNINGS=()

section() {
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  $1"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

ok() {
  echo -e "  ${GREEN}✓${NC} $1"
}

fail() {
  echo -e "  ${RED}✗${NC} $1"
  ISSUES+=("$1")
}

warn() {
  echo -e "  ${YELLOW}⚠${NC} $1"
  WARNINGS+=("$1")
}

info() {
  echo -e "    $1"
}

# =============================================================================
section "1. ENVIRONMENT VARIABLES (/etc/environment)"
# =============================================================================

if [ -f /etc/environment ]; then
  ok "/etc/environment exists"

  # Source environment variables
  set -a
  source /etc/environment 2>/dev/null
  set +a

  # Check required variables
  for var in POSTGRES_HOST POSTGRES_PORT POSTGRES_USER POSTGRES_PASSWORD POSTGRES_DATABASE ECR_REPOSITORY_URL AWS_REGION CLICKHOUSE_DATA_DEVICE; do
    val="${!var}"
    if [ -z "$val" ]; then
      fail "Missing environment variable: $var"
    else
      if [ "$var" = "POSTGRES_PASSWORD" ]; then
        ok "$var is set (value hidden)"
      else
        ok "$var = $val"
      fi
    fi
  done
else
  fail "/etc/environment does not exist - user_data may not have run"
fi

# =============================================================================
section "2. EBS DATA VOLUME"
# =============================================================================

DATA_DEVICE="${CLICKHOUSE_DATA_DEVICE:-/dev/nvme1n1}"
MOUNT_POINT="/var/lib/clickhouse"

echo "  Looking for data device: $DATA_DEVICE"
echo ""

# Show all block devices
echo "  Block devices:"
lsblk 2>/dev/null | sed 's/^/    /'
echo ""

if [ -b "$DATA_DEVICE" ]; then
  ok "Data device $DATA_DEVICE exists"
else
  # Check for alternative NVMe devices
  ALT_FOUND=""
  ROOT_DEVICE=$(findmnt -n -o SOURCE / 2>/dev/null | sed 's/p[0-9]*$//')
  for nvme_dev in /dev/nvme*n1; do
    [ -b "$nvme_dev" ] || continue
    [ "$nvme_dev" = "$ROOT_DEVICE" ] && continue
    ALT_FOUND="$nvme_dev"
  done
  if [ -n "$ALT_FOUND" ]; then
    warn "Configured device $DATA_DEVICE not found, but $ALT_FOUND exists"
  else
    fail "Data device $DATA_DEVICE not found and no alternative NVMe device detected"
    info "The EBS volume may not have attached. Check cloud-init-output.log."
  fi
fi

if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
  ok "$MOUNT_POINT is mounted"
  df -h "$MOUNT_POINT" 2>/dev/null | tail -1 | sed 's/^/    /'
else
  fail "$MOUNT_POINT is NOT mounted"
  info "ClickHouse data directory is not available."
fi

# Check ownership
if [ -d "$MOUNT_POINT" ]; then
  OWNER=$(stat -c '%u:%g' "$MOUNT_POINT" 2>/dev/null)
  if [ "$OWNER" = "101:101" ]; then
    ok "$MOUNT_POINT ownership is 101:101 (correct for ClickHouse container)"
  else
    warn "$MOUNT_POINT ownership is $OWNER (expected 101:101)"
  fi
fi

# =============================================================================
section "3. DOCKER SERVICE"
# =============================================================================

if systemctl is-active --quiet docker 2>/dev/null; then
  ok "Docker service is running"
else
  fail "Docker service is NOT running"
  info "Status:"
  systemctl status docker 2>&1 | head -10 | sed 's/^/    /'
fi

if command -v docker &>/dev/null; then
  ok "Docker binary found: $(which docker)"
  DOCKER_VERSION=$(docker --version 2>/dev/null)
  ok "Docker version: $DOCKER_VERSION"
else
  fail "Docker binary not found in PATH"
fi

if command -v docker &>/dev/null && docker info &>/dev/null; then
  ok "Docker daemon is responsive"
else
  fail "Docker daemon is not responsive (permission issue or not running)"
fi

# =============================================================================
section "4. DOCKER COMPOSE CONFIGURATION"
# =============================================================================

CLICKHOUSE_DIR="/home/ec2-user/clickhouse"

if [ -d "$CLICKHOUSE_DIR" ]; then
  ok "ClickHouse directory exists: $CLICKHOUSE_DIR"
else
  fail "ClickHouse directory NOT found: $CLICKHOUSE_DIR"
  info "The Packer AMI may not have been used, or files were not provisioned."
fi

if [ -f "$CLICKHOUSE_DIR/docker-compose.yml" ]; then
  ok "docker-compose.yml exists"
else
  fail "docker-compose.yml NOT found in $CLICKHOUSE_DIR"
fi

if [ -f "$CLICKHOUSE_DIR/config/named_collections.xml" ]; then
  ok "named_collections.xml exists"
  # Check if placeholders were substituted
  if grep -q '__POSTGRES_HOST__' "$CLICKHOUSE_DIR/config/named_collections.xml"; then
    fail "named_collections.xml still contains unsubstituted placeholders"
    info "start-clickhouse.sh may not have run or failed before sed substitution."
  else
    ok "named_collections.xml placeholders have been substituted"
  fi
else
  fail "named_collections.xml NOT found"
fi

for cfg in config.xml users.xml init-permissions.sql; do
  if [ -f "$CLICKHOUSE_DIR/config/$cfg" ]; then
    ok "config/$cfg exists"
  else
    warn "config/$cfg NOT found"
  fi
done

# =============================================================================
section "5. DOCKER CONTAINERS"
# =============================================================================

if [ -f "$CLICKHOUSE_DIR/docker-compose.yml" ]; then
  cd "$CLICKHOUSE_DIR"

  echo "  Container status:"
  docker compose ps 2>/dev/null | sed 's/^/    /'
  echo ""

  CONTAINER_STATUS=$(docker compose ps --format '{{.State}}' 2>/dev/null | head -1)
  if [ "$CONTAINER_STATUS" = "running" ]; then
    ok "ClickHouse container is running"
  elif [ -n "$CONTAINER_STATUS" ]; then
    fail "ClickHouse container state: $CONTAINER_STATUS"
  else
    fail "No ClickHouse container found (never started or was removed)"
  fi

  # Show recent logs if container exists
  LOGS=$(docker compose logs --tail=30 2>/dev/null)
  if [ -n "$LOGS" ]; then
    echo ""
    echo "  Recent container logs (last 30 lines):"
    echo "$LOGS" | sed 's/^/    /'
  fi
else
  fail "Cannot check containers - docker-compose.yml missing"
fi

# =============================================================================
section "6. DOCKER IMAGES"
# =============================================================================

echo "  Available images:"
docker images 2>/dev/null | sed 's/^/    /'
echo ""

# Check if the clickhouse image is available
if docker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | grep -q "clickhouse"; then
  ok "ClickHouse image is available locally"
else
  warn "No ClickHouse image found locally - may need to pull from Docker Hub"
  if [ -n "$ECR_REPOSITORY_URL" ]; then
    info "ECR URL configured: $ECR_REPOSITORY_URL"
    info "Check if ECR login was performed and image was pulled."
  fi
fi

# =============================================================================
section "7. NETWORK CONNECTIVITY"
# =============================================================================

# Check if ClickHouse port is listening
if ss -tlnp 2>/dev/null | grep -q ':8123'; then
  ok "Port 8123 (HTTP) is listening"
else
  fail "Port 8123 (HTTP) is NOT listening"
fi

if ss -tlnp 2>/dev/null | grep -q ':9000'; then
  ok "Port 9000 (native) is listening"
else
  fail "Port 9000 (native) is NOT listening"
fi

# Test PostgreSQL connectivity (if variables are set)
if [ -n "$POSTGRES_HOST" ] && [ -n "$POSTGRES_PORT" ]; then
  if timeout 5 bash -c "echo >/dev/tcp/$POSTGRES_HOST/$POSTGRES_PORT" 2>/dev/null; then
    ok "Can reach PostgreSQL at $POSTGRES_HOST:$POSTGRES_PORT"
  else
    warn "Cannot reach PostgreSQL at $POSTGRES_HOST:$POSTGRES_PORT"
  fi
fi

# =============================================================================
section "8. CLOUD-INIT / USER_DATA LOG"
# =============================================================================

LOG_FILE="/var/log/cloud-init-output.log"
if [ -f "$LOG_FILE" ]; then
  ok "cloud-init-output.log exists"

  # Check for errors in the log
  ERROR_COUNT=$(grep -ci 'error\|failed\|fatal' "$LOG_FILE" 2>/dev/null || echo "0")
  if [ "$ERROR_COUNT" -gt 0 ]; then
    warn "Found $ERROR_COUNT lines with error/failed/fatal in cloud-init log"
    echo ""
    echo "  Error lines from cloud-init-output.log:"
    grep -i 'error\|failed\|fatal' "$LOG_FILE" 2>/dev/null | tail -20 | sed 's/^/    /'
  else
    ok "No obvious errors in cloud-init log"
  fi

  # Show the tail of the log
  echo ""
  echo "  Last 20 lines of cloud-init-output.log:"
  tail -20 "$LOG_FILE" | sed 's/^/    /'
else
  warn "cloud-init-output.log not found"
fi

# =============================================================================
section "9. START SCRIPT"
# =============================================================================

START_SCRIPT="/home/ec2-user/clickhouse/scripts/start-clickhouse.sh"
if [ -f "$START_SCRIPT" ]; then
  ok "start-clickhouse.sh exists"
  if [ -x "$START_SCRIPT" ]; then
    ok "start-clickhouse.sh is executable"
  else
    fail "start-clickhouse.sh is NOT executable"
  fi
else
  fail "start-clickhouse.sh NOT found at $START_SCRIPT"
fi

# =============================================================================
section "10. DISK SPACE"
# =============================================================================

echo "  Filesystem usage:"
df -h 2>/dev/null | grep -v tmpfs | sed 's/^/    /'

ROOT_USAGE=$(df / 2>/dev/null | tail -1 | awk '{print $5}' | tr -d '%')
if [ -n "$ROOT_USAGE" ] && [ "$ROOT_USAGE" -gt 90 ]; then
  fail "Root filesystem is ${ROOT_USAGE}% full"
else
  ok "Root filesystem usage: ${ROOT_USAGE}%"
fi

# =============================================================================
section "DIAGNOSIS SUMMARY"
# =============================================================================

echo ""
if [ ${#ISSUES[@]} -eq 0 ] && [ ${#WARNINGS[@]} -eq 0 ]; then
  echo -e "  ${GREEN}All checks passed! ClickHouse should be running.${NC}"
  echo "  If it's still not working, check the container logs in detail."
elif [ ${#ISSUES[@]} -eq 0 ]; then
  echo -e "  ${YELLOW}No critical issues found, but there are ${#WARNINGS[@]} warning(s).${NC}"
else
  echo -e "  ${RED}Found ${#ISSUES[@]} issue(s) and ${#WARNINGS[@]} warning(s):${NC}"
  echo ""
  echo "  Issues:"
  for issue in "${ISSUES[@]}"; do
    echo -e "    ${RED}✗${NC} $issue"
  done
  if [ ${#WARNINGS[@]} -gt 0 ]; then
    echo ""
    echo "  Warnings:"
    for warning in "${WARNINGS[@]}"; do
      echo -e "    ${YELLOW}⚠${NC} $warning"
    done
  fi
fi

echo ""

# Provide likely root cause
if [ ${#ISSUES[@]} -gt 0 ]; then
  echo -e "  ${YELLOW}Likely root cause:${NC}"

  if printf '%s\n' "${ISSUES[@]}" | grep -q "/etc/environment does not exist"; then
    echo "    → EC2 user_data did not execute. The instance may have been launched"
    echo "      without user_data, or cloud-init failed early."
  elif printf '%s\n' "${ISSUES[@]}" | grep -q "ClickHouse directory NOT found"; then
    echo "    → The Packer-built AMI was not used. The instance is running a base"
    echo "      Amazon Linux AMI without ClickHouse pre-installed."
    echo "      Fix: Build the Packer AMI and update clickhouse_ami_id, or let"
    echo "      Terraform auto-detect it."
  elif printf '%s\n' "${ISSUES[@]}" | grep -q "Docker service is NOT running"; then
    echo "    → Docker is not running. It may not be installed (wrong AMI) or"
    echo "      failed to start. Check: sudo systemctl status docker"
  elif printf '%s\n' "${ISSUES[@]}" | grep -q "NOT mounted"; then
    echo "    → The EBS data volume failed to mount. The volume may not have"
    echo "      attached in time, or the device path is wrong."
    echo "      Fix: Check cloud-init-output.log for attachment errors, then run:"
    echo "      sudo /home/ec2-user/clickhouse/scripts/start-clickhouse.sh"
  elif printf '%s\n' "${ISSUES[@]}" | grep -q "unsubstituted placeholders"; then
    echo "    → start-clickhouse.sh ran but failed to substitute config values."
    echo "      Check that /etc/environment has the correct POSTGRES_* variables."
    echo "      Fix: Re-run: sudo /home/ec2-user/clickhouse/scripts/start-clickhouse.sh"
  elif printf '%s\n' "${ISSUES[@]}" | grep -q "container state"; then
    echo "    → The ClickHouse container started but crashed. Check the container"
    echo "      logs above for the specific error (config issue, permission denied, etc)."
    echo "      Common causes: wrong volume permissions, bad config XML, port conflict."
  elif printf '%s\n' "${ISSUES[@]}" | grep -q "No ClickHouse container found"; then
    echo "    → docker compose up was never run or failed immediately."
    echo "      Fix: cd /home/ec2-user/clickhouse && sudo docker compose up -d"
    echo "      Then check: sudo docker compose logs"
  else
    echo "    → Multiple issues detected. Address them in order from top to bottom."
  fi
  echo ""
fi

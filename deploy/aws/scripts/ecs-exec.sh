#!/usr/bin/env bash
#
# Run a short command synchronously in the seqr-web ECS Fargate container and
# print its output to stdout, suitable for scripting / redirecting to a file.
#
# Usage:
#   ./ecs-exec.sh "python manage.py export_pedigree R0015_acg_001" > R0015.ped
#
# Unlike ecs-run.sh (which detaches via nohup for long-running jobs), this waits
# for the command to finish. Only the command's output is written to stdout;
# discovery messages and Session Manager noise go to stderr or are discarded.
# The remote command's exit code is propagated.
#
# ECS Exec runs through a pty, which merges stdout and stderr. To keep them
# apart, the remote command's stderr is captured to a temp file in the container
# and replayed after a separate marker; it is written to local stderr here.
# Use ecs-run.sh for anything that may outlive the SSM session.

set -euo pipefail

COMMAND="${1:-}"
REGION="${AWS_DEFAULT_REGION:-ap-southeast-2}"

if [[ -z "${COMMAND}" ]]; then
  echo "Usage: $0 <command>" >&2
  echo "" >&2
  echo "Example:" >&2
  echo "  $0 \"python manage.py export_pedigree R0015_acg_001\" > R0015.ped" >&2
  exit 1
fi

# Auto-discover cluster
CLUSTER=$(aws ecs list-clusters --region "${REGION}" --output text --query \
  "clusterArns[?contains(@, 'seqr')] | [0]" 2>/dev/null || true)
if [[ -z "${CLUSTER}" || "${CLUSTER}" == "None" ]]; then
  echo "ERROR: Could not find a seqr ECS cluster." >&2
  exit 1
fi

# Auto-discover service
SERVICE=$(aws ecs list-services --cluster "${CLUSTER}" --region "${REGION}" --output text --query \
  "serviceArns[?contains(@, 'seqr-web')] | [0]" 2>/dev/null || true)
if [[ -z "${SERVICE}" || "${SERVICE}" == "None" ]]; then
  echo "ERROR: Could not find a seqr-web ECS service." >&2
  exit 1
fi

# Find a running task
TASK_ARN=$(aws ecs list-tasks \
  --cluster "${CLUSTER}" \
  --service-name "${SERVICE}" \
  --desired-status RUNNING \
  --region "${REGION}" \
  --output text \
  --query "taskArns[0]" 2>/dev/null || true)
if [[ -z "${TASK_ARN}" || "${TASK_ARN}" == "None" ]]; then
  echo "ERROR: No running tasks found." >&2
  exit 1
fi

CONTAINER="seqr-web"

# Unique markers delimit the command's output from Session Manager banners.
MARKER="ECSEXEC_$(date +%s)_$$_${RANDOM}"

# Base64-encode the wrapped script so arbitrary quoting in COMMAND survives
# the --command string untouched.
REMOTE_SCRIPT="ERR=\$(mktemp); echo ${MARKER}_BEGIN; ( ${COMMAND}
) 2>\"\$ERR\"; RC=\$?; echo ${MARKER}_STDERR; cat \"\$ERR\"; rm -f \"\$ERR\"; echo ${MARKER}_END_RC=\$RC"
ENCODED=$(printf '%s' "${REMOTE_SCRIPT}" | base64 | tr -d '\n')

# session-manager-plugin aborts ("Cannot perform start session: EOF") if stdin
# hits EOF, but inheriting our stdin would swallow input when called from a
# `while read` loop. Feed it from a FIFO held open (with no data) by sleep.
STDIN_DIR=$(mktemp -d)
mkfifo "${STDIN_DIR}/stdin"
sleep 86400 > "${STDIN_DIR}/stdin" &
SLEEP_PID=$!
trap 'kill ${SLEEP_PID} 2>/dev/null || true; rm -rf "${STDIN_DIR}"' EXIT

RAW_OUTPUT=$(aws ecs execute-command \
  --cluster "${CLUSTER}" \
  --task "${TASK_ARN}" \
  --container "${CONTAINER}" \
  --interactive \
  --region "${REGION}" \
  --command "/bin/bash -c 'echo ${ENCODED} | base64 -d | /bin/bash'" 2>&1 < "${STDIN_DIR}/stdin") || {
  echo "ERROR: aws ecs execute-command failed:" >&2
  echo "${RAW_OUTPUT}" >&2
  exit 1
}

RAW_OUTPUT=$(printf '%s\n' "${RAW_OUTPUT}" | tr -d '\r')

RC_FILE="${STDIN_DIR}/rc"

# Split the session output into stdout / stderr sections. Markers are matched
# anywhere in a line, since terminal escape codes or a missing trailing newline
# can leave other text in front of them; that text is passed through unchanged.
awk -v begin="${MARKER}_BEGIN" -v errmark="${MARKER}_STDERR" -v end="${MARKER}_END_RC=" -v rcfile="${RC_FILE}" '
  (i = index($0, begin)) > 0 { section = 1; next }
  (i = index($0, errmark)) > 0 { if (i > 1) printf "%s", substr($0, 1, i - 1); section = 2; next }
  (i = index($0, end)) > 0 {
    if (i > 1) printf "%s", substr($0, 1, i - 1) > "/dev/stderr"
    rc = substr($0, i + length(end)); sub(/[^0-9].*/, "", rc)
    print rc > rcfile
    section = 3; next
  }
  section == 1 { print }
  section == 2 { print > "/dev/stderr" }
' <<< "${RAW_OUTPUT}"

RC=$(cat "${RC_FILE}" 2>/dev/null || true)
if [[ -z "${RC}" ]]; then
  echo "ERROR: Command did not complete (session may have been cut off). Raw session output:" >&2
  echo "${RAW_OUTPUT}" >&2
  exit 1
fi
exit "${RC}"

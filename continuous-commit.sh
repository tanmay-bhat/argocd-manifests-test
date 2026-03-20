#!/bin/bash
set -euo pipefail

# Continuously pushes commits to charts/chart-1/ every 60 seconds.
# This triggers reconciliation for ALL apps (HEAD changes for everyone),
# but only chart-1's path actually has file changes.
#
# Usage:
#   ./continuous-commit.sh              # default: 60s interval, 10 commits
#   ./continuous-commit.sh 30 20        # 30s interval, 20 commits
#   ./continuous-commit.sh 60 0         # 60s interval, run forever

INTERVAL="${1:-60}"
MAX_COMMITS="${2:-10}"
COUNTER=0
TARGET_FILE="charts/chart-1/values.yaml"
BRANCH="$(git rev-parse --abbrev-ref HEAD)"

echo "=== Continuous Commit Script ==="
echo "target file:  ${TARGET_FILE}"
echo "interval:     ${INTERVAL}s"
echo "max commits:  ${MAX_COMMITS} (0 = infinite)"
echo "branch:       ${BRANCH}"
echo "started at:   $(date '+%Y-%m-%d %H:%M:%S')"
echo "================================"
echo ""

while true; do
  COUNTER=$((COUNTER + 1))
  TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S')"

  # update the values file with a new timestamp
  cat <<EOF > "${TARGET_FILE}"
config:
  name: "dummy-config-1"
  # commit ${COUNTER} at ${TIMESTAMP}
  iteration: "${COUNTER}"
EOF

  git add "${TARGET_FILE}"
  git commit -m "test: commit ${COUNTER} - update chart-1 values at ${TIMESTAMP}"
  git push origin "${BRANCH}"

  echo "[${TIMESTAMP}] commit ${COUNTER} pushed"

  if [[ "${MAX_COMMITS}" -gt 0 && "${COUNTER}" -ge "${MAX_COMMITS}" ]]; then
    echo ""
    echo "reached ${MAX_COMMITS} commits, stopping."
    echo "ended at: $(date '+%Y-%m-%d %H:%M:%S')"
    break
  fi

  sleep "${INTERVAL}"
done

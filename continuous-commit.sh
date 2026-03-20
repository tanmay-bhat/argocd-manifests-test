#!/bin/bash
set -euo pipefail

# Continuously pushes commits to charts/chart-1/ every 60 seconds.
# Simulates prod behavior where image-updater writes to env-specific values.
#
# This triggers HEAD change for ALL apps, but only chart-1's path has changes.
# With manifest-generate-paths, only app-1 should do full reconciliation.
#
# Usage:
#   ./continuous-commit.sh              # default: 60s interval, 10 commits
#   ./continuous-commit.sh 30 20        # 30s interval, 20 commits
#   ./continuous-commit.sh 60 0         # 60s interval, run forever

INTERVAL="${1:-60}"
MAX_COMMITS="${2:-10}"
COUNTER=0
TARGET_FILE="charts/chart-1/lab-values.yaml"
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

  # update the env-specific values file (simulates image-updater write-back)
  cat <<EOF > "${TARGET_FILE}"
config:
  name: "chart-1-lab-override"

replicaCount: 1

environment: "lab"
region: "local"

# image-updater simulation
image:
  tag: "main-${COUNTER}-$(date +%s)"

# commit ${COUNTER} at ${TIMESTAMP}
EOF

  git add "${TARGET_FILE}"
  git commit -m "test: commit ${COUNTER} - update chart-1 lab-values at ${TIMESTAMP}"
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

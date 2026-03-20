#!/bin/bash
set -euo pipefail

# Generates 350 SINGLE-SOURCE bulk apps + 4 individual apps for Phase 3 testing.
# Single-source = no ref: values, valueFiles resolved relative to chart path.
# This isolates whether manifest-generate-paths works on v3.3.4 without multi-source.

CHART_DIR="bulk-resources"
APPS_DIR="argocd-apps"
APPS_FILE="${APPS_DIR}/all-apps.yaml"
REPO_URL="https://github.com/tanmay-bhat/argocd-manifests-test"
ENABLE_MANIFEST_PATHS="${1:-false}"

echo "=== ArgoCD Reconciliation Lab — Single-Source Setup ==="
echo "manifest-generate-paths: ${ENABLE_MANIFEST_PATHS}"
echo ""

# --- Generate 350 SINGLE-SOURCE bulk apps ---
echo "Generating 350 single-source Application manifests..."
mkdir -p "${APPS_DIR}"
> "${APPS_FILE}"

for i in $(seq 1 350); do
  MANIFEST_PATH_ANNOTATION=""
  if [[ "${ENABLE_MANIFEST_PATHS}" == "true" ]]; then
    MANIFEST_PATH_ANNOTATION="    argocd.argoproj.io/manifest-generate-paths: '/${CHART_DIR}'"
  fi

  cat <<EOF >> "${APPS_FILE}"
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: bulk-app-${i}
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
  annotations:
${MANIFEST_PATH_ANNOTATION:-    app: "bulk-app-${i}"}
spec:
  project: default
  source:
    repoURL: '${REPO_URL}'
    targetRevision: HEAD
    path: ${CHART_DIR}
    helm:
      releaseName: bulk-app-${i}
      valueFiles:
        - values.yaml
        - lab-values.yaml
  destination:
    server: 'https://kubernetes.default.svc'
    namespace: bulk-app-${i}-ns
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
---
EOF
done

echo "Generated 350 single-source Applications in '${APPS_FILE}'"

# --- Generate individual apps (single-source) ---
echo "Generating individual single-source app manifests..."
for i in 1 2 3 4; do
  MANIFEST_PATH_ANNOTATION=""
  if [[ "${ENABLE_MANIFEST_PATHS}" == "true" ]]; then
    MANIFEST_PATH_ANNOTATION="  annotations:
    argocd.argoproj.io/manifest-generate-paths: '/charts/chart-${i}'"
  fi

  cat <<EOF > "apps/app-${i}.yaml"
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: app-${i}
  namespace: argocd
${MANIFEST_PATH_ANNOTATION}
spec:
  project: default
  source:
    repoURL: '${REPO_URL}'
    targetRevision: HEAD
    path: charts/chart-${i}
    helm:
      releaseName: app-${i}
      valueFiles:
        - values.yaml
        - lab-values.yaml
  destination:
    server: 'https://kubernetes.default.svc'
    namespace: default
EOF
done

echo "Individual apps generated."

# --- Apply ---
echo ""
echo "Applying Applications..."
kubectl apply -f "${APPS_FILE}" -n argocd
for i in 1 2 3 4; do
  kubectl apply -f "apps/app-${i}.yaml" -n argocd
done
echo "Done! 354 single-source apps applied."

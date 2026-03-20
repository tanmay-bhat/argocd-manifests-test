#!/bin/bash
set -euo pipefail

CHART_DIR="bulk-resources"
APPS_DIR="argocd-apps"
APPS_FILE="${APPS_DIR}/all-apps.yaml"
REPO_URL="https://github.com/tanmay-bhat/argocd-manifests-test"
ENABLE_MANIFEST_PATHS="${1:-false}"  # pass "true" as first arg to enable annotation

echo "=== ArgoCD Reconciliation Lab Setup ==="
echo "manifest-generate-paths: ${ENABLE_MANIFEST_PATHS}"
echo "argocd version: v3.3.4 (chart 9.4.12)"
echo ""

# --- Install ArgoCD via Helm ---
echo "Installing ArgoCD via Helm chart..."
helm repo add argo https://argoproj.github.io/argo-helm 2>/dev/null || true
helm repo update argo

helm upgrade --install argocd argo/argo-cd \
  --version 9.4.12 \
  -n argocd --create-namespace \
  -f argocd-values.yaml \
  --wait --timeout 5m

echo "ArgoCD v3.3.4 installed."

# --- Generate 350 bulk ArgoCD Applications (multi-source, matching prod pattern) ---
# Source 1: chart path (bulk-resources/)
# Source 2: same repo with ref: values (for $values/ file references)
echo "Generating 350 multi-source ArgoCD Application manifests..."
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
  sources:
    - repoURL: '${REPO_URL}'
      targetRevision: HEAD
      path: ${CHART_DIR}
      helm:
        releaseName: bulk-app-${i}
        ignoreMissingValueFiles: true
        valueFiles:
          - '\$values/${CHART_DIR}/values.yaml'
          - '\$values/${CHART_DIR}/lab-values.yaml'
    - repoURL: '${REPO_URL}'
      targetRevision: HEAD
      ref: values
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

echo "Generated 350 multi-source Applications in '${APPS_FILE}'"

# --- Generate individual app manifests (app-1 through app-4, multi-source) ---
echo "Generating individual multi-source app manifests..."
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
  sources:
    - repoURL: '${REPO_URL}'
      targetRevision: HEAD
      path: charts/chart-${i}
      helm:
        releaseName: app-${i}
        ignoreMissingValueFiles: true
        valueFiles:
          - '\$values/charts/chart-${i}/values.yaml'
          - '\$values/charts/chart-${i}/lab-values.yaml'
    - repoURL: '${REPO_URL}'
      targetRevision: HEAD
      ref: values
  destination:
    server: 'https://kubernetes.default.svc'
    namespace: default
EOF
done

echo "Individual apps generated."

# --- Apply everything ---
echo ""
echo "Applying ArgoCD Applications to the cluster..."
kubectl apply -f "${APPS_FILE}" -n argocd
for i in 1 2 3 4; do
  kubectl apply -f "apps/app-${i}.yaml" -n argocd
done
echo "All done! 354 multi-source ArgoCD applications applied."

# --- Prometheus ---
echo ""
echo "Installing Prometheus Operator (skip if already installed)..."
helm upgrade --install k8s oci://ghcr.io/prometheus-community/charts/kube-prometheus-stack \
  -n monitoring --create-namespace 2>/dev/null || echo "Prometheus stack already installed, skipping."

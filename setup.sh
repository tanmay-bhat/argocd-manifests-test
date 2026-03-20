#!/bin/bash
set -euo pipefail

CHART_DIR="bulk-resources"
APPS_DIR="argocd-apps"
APPS_FILE="${APPS_DIR}/all-apps.yaml"
REPO_URL="https://github.com/tanmay-bhat/argocd-manifests-test"
ENABLE_MANIFEST_PATHS="${1:-false}"  # pass "true" as first arg to enable annotation

echo "=== ArgoCD Reconciliation Lab Setup ==="
echo "manifest-generate-paths annotation: ${ENABLE_MANIFEST_PATHS}"
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

echo "ArgoCD installed."

# --- Helm chart for bulk apps ---
echo "Creating Helm chart in '${CHART_DIR}'..."
mkdir -p "${CHART_DIR}/templates"

cat <<EOF > "${CHART_DIR}/Chart.yaml"
apiVersion: v2
name: bulk-resources
description: A Helm chart that generates 10 ConfigMaps and 10 Secrets
type: application
version: 0.1.0
appVersion: "1.0.0"
EOF

cat <<'EOF' > "${CHART_DIR}/templates/configmap.yaml"
{{- $relName := .Release.Name -}}
{{- range $i, $e := until 10 }}
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ $relName }}-configmap-{{ $i }}
  labels:
    app.kubernetes.io/instance: {{ $relName }}
data:
  resource-index: "{{ $i }}"
  description: "ConfigMap {{ $i }} for release {{ $relName }}"
---
{{- end }}
EOF

cat <<'EOF' > "${CHART_DIR}/templates/secret.yaml"
{{- $relName := .Release.Name -}}
{{- range $i, $e := until 10 }}
apiVersion: v1
kind: Secret
metadata:
  name: {{ $relName }}-secret-{{ $i }}
  labels:
    app.kubernetes.io/instance: {{ $relName }}
type: Opaque
stringData:
  resource-index: "{{ $i }}"
  description: "Secret {{ $i }} for release {{ $relName }}"
---
{{- end }}
EOF

echo "Helm chart created."

# --- Generate 350 bulk ArgoCD Applications ---
echo "Generating 350 ArgoCD Application manifests..."
mkdir -p "${APPS_DIR}"
> "${APPS_FILE}"

for i in $(seq 1 350); do
  ANNOTATION_BLOCK=""
  if [[ "${ENABLE_MANIFEST_PATHS}" == "true" ]]; then
    ANNOTATION_BLOCK="    argocd.argoproj.io/manifest-generate-paths: '/${CHART_DIR}'"
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
${ANNOTATION_BLOCK:-    app: "bulk-app-${i}"}
spec:
  project: default
  source:
    repoURL: '${REPO_URL}'
    targetRevision: HEAD
    path: ${CHART_DIR}
    helm:
      releaseName: bulk-app-${i}
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

echo "Generated 350 ArgoCD Applications in '${APPS_FILE}'"

# --- Update individual app manifests (app-1 through app-4) ---
echo "Updating individual app manifests..."
for i in 1 2 3 4; do
  ANNOTATION_BLOCK=""
  if [[ "${ENABLE_MANIFEST_PATHS}" == "true" ]]; then
    ANNOTATION_BLOCK="  annotations:
    argocd.argoproj.io/manifest-generate-paths: '/charts/chart-${i}'"
  fi

  cat <<EOF > "apps/app-${i}.yaml"
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: app-${i}
  namespace: argocd
${ANNOTATION_BLOCK}
spec:
  project: default
  source:
    repoURL: '${REPO_URL}'
    targetRevision: HEAD
    path: charts/chart-${i}
  destination:
    server: 'https://kubernetes.default.svc'
    namespace: default
EOF
done

echo "Individual apps updated."

# --- Apply everything ---
echo ""
echo "Applying ArgoCD Applications to the cluster..."
kubectl apply -f "${APPS_FILE}" -n argocd
for i in 1 2 3 4; do
  kubectl apply -f "apps/app-${i}.yaml" -n argocd
done
echo "All done! 354 ArgoCD applications applied."

# --- Prometheus ---
echo ""
echo "Installing Prometheus Operator (skip if already installed)..."
helm upgrade --install k8s oci://ghcr.io/prometheus-community/charts/kube-prometheus-stack \
  -n monitoring --create-namespace 2>/dev/null || echo "Prometheus stack already installed, skipping."

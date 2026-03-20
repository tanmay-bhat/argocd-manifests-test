#!/bin/bash
set -euo pipefail

CHART_DIR="bulk-resources"
APPS_DIR="argocd-apps"
APPS_FILE="${APPS_DIR}/all-apps.yaml"

echo "Creating Helm chart in '${CHART_DIR}'..."
mkdir -p "${CHART_DIR}/templates"

# Create Chart.yaml
cat <<EOF > "${CHART_DIR}/Chart.yaml"
apiVersion: v2
name: bulk-resources
description: A Helm chart that generates 10 ConfigMaps and 10 Secrets
type: application
version: 0.1.0
appVersion: "1.0.0"
EOF

# Create ConfigMap template (generates 10 ConfigMaps)
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

# Create Secret template (generates 10 Secrets)
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

echo "Helm chart created successfully."

echo "Generating 350 ArgoCD Application manifests..."
mkdir -p "${APPS_DIR}"
> "${APPS_FILE}" # Clear file if it exists

for i in {1..350}; do
  cat <<EOF >> "${APPS_FILE}"
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: bulk-app-${i}
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: 'https://github.com/tanmay-bhat/argocd-manifests-test'
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

echo "Successfully generated 350 ArgoCD Applications in '${APPS_FILE}'"

echo "Applying ArgoCD Applications to the cluster..."
kubectl apply -f "${APPS_FILE}" -n argocd
echo "All done! 350 ArgoCD applications have been applied."

echo "Installing Prometheus Operator..."
helm install k8s oci://ghcr.io/prometheus-community/charts/kube-prometheus-stack -n monitoring --create-namespace

echo "Applying ArgoCD ServiceMonitors..."
kubectl apply -f argocd-metrics.yml

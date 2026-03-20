#!/bin/bash
set -euo pipefail

# Patches the ArgoCD application-controller to enable sync timeout jitter.
# ref: https://argo-cd.readthedocs.io/en/stable/operator-manual/high_availability/#application-sync-timeout-jitter
#
# --app-resync-jitter: randomizes reconciliation timing across the resync period
#   to prevent thundering herd when all 350 apps fire at the same 180s mark.
#
# This is safe to apply — it just spreads reconciliation evenly across the window
# instead of all apps hitting the controller at once.

echo "=== Enabling app-resync-jitter on ArgoCD application-controller ==="

# Check current args
echo "Current controller args:"
kubectl get sts argocd-application-controller -n argocd \
  -o jsonpath='{.spec.template.spec.containers[0].args}' | tr ',' '\n'
echo ""

# Patch: add --app-resync-jitter=60
# This spreads the 180s reconciliation across a 60s jitter window (120s-180s)
kubectl patch sts argocd-application-controller -n argocd --type='json' \
  -p='[
    {
      "op": "add",
      "path": "/spec/template/spec/containers/0/args/-",
      "value": "--app-resync-jitter=60"
    }
  ]'

echo ""
echo "Patched. Controller will restart."
echo "Waiting for rollout..."
kubectl rollout status sts/argocd-application-controller -n argocd --timeout=120s
echo "Done. Jitter is now active."

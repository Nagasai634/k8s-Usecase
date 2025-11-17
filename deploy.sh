#!/usr/bin/env bash
set -euo pipefail

NAMESPACE=${1:-java-gradle-ns}
IMAGE_URI="${2:?IMAGE_URI required (full GAR path)}"

echo "Apply namespace"
kubectl apply -f k8s/namespace.yaml

echo "Apply ConfigMap"
kubectl apply -f k8s/configmap.yaml -n "${NAMESPACE}"

echo "Apply BackendConfig and Service"
kubectl apply -f k8s/backendconfig.yaml -n "${NAMESPACE}"
kubectl apply -f k8s/service.yaml -n "${NAMESPACE}"

echo "Apply Deployment (manifest uses placeholder image; we patch below)"
kubectl apply -f k8s/deployment.yaml -n "${NAMESPACE}"

echo "Patch deployment image -> ${IMAGE_URI}"
kubectl -n "${NAMESPACE}" set image deployment/java-gradle-deployment java-gradle="${IMAGE_URI}" --record

echo "Apply Ingress and HPA"
kubectl apply -f k8s/ingress.yaml -n "${NAMESPACE}"
kubectl apply -f k8s/hpa.yaml -n "${NAMESPACE}"

echo "Wait for rollout"
kubectl -n "${NAMESPACE}" rollout status deployment/java-gradle-deployment --timeout=180s

echo "Pods:"
kubectl -n "${NAMESPACE}" get pods -l app=java-gradle -o wide
kubectl -n "${NAMESPACE}" get ingress java-gradle-ingress -o wide || true

#!/usr/bin/env bash
set -euo pipefail
export KUBECONFIG="${MC_KUBECONFIG:-/tmp/ai-lab-multicluster.kubeconfig}"
kind delete cluster --name ai-lab-manager
kind delete cluster --name ai-lab-worker1

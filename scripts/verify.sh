#!/usr/bin/env bash
# Quick health overview of every layer.
set -uo pipefail
section() { printf '\n\033[1m## %s\033[0m\n' "$*"; }
section "Nodes & GPUs"
kubectl get nodes -L nvidia.com/gpu.product -o custom-columns='NAME:.metadata.name,STATUS:.status.conditions[-1].type,GPU:.status.allocatable.nvidia\.com/gpu,PRODUCT:.metadata.labels.nvidia\.com/gpu\.product'
section "Cilium";            kubectl -n kube-system get ds cilium
section "GPU operator";      kubectl -n gpu-operator get pods --no-headers 2>/dev/null | awk '{print $3}' | sort | uniq -c
section "Gateway";           kubectl get gateway -A; kubectl get aigatewayroute -A
section "Inference pods";    kubectl -n llm-serving get pods -o wide
section "Kueue";             kubectl get clusterqueue; kubectl get workloads -A
section "Training";          kubectl get trainjob,rayjob,raycluster -A 2>/dev/null
section "Autoscaling";       kubectl get scaledobject -A

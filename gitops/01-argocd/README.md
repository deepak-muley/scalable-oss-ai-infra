# Argo CD

Argo CD watches git and keeps clusters matching it. This install is tuned
for this platform:

| Setting (values.yaml) | Why |
|---|---|
| `server.insecure` | lab: TLS terminated by port-forward / your gateway; avoids redirect loops |
| `configs.repositories` with `enableOCI` | Kueue, LWS, Envoy Gateway and AI Gateway ship Helm charts **only** as OCI artifacts |
| `kustomize.buildOptions` | Kubeflow Trainer installs via kustomize from its git repo |
| `resource.customizations.health.argoproj.io_Application` | restores Application health so **sync waves between apps** work |
| `resource.customizations.ignoreDifferences` for webhooks / CRDs / APIServices | operators (Kueue, KEDA, Kyverno, cert-manager cainjector) inject `caBundle` at runtime; without this Argo shows them OutOfSync forever and selfHeal fights the operator |
| `resource.exclusions` for Cilium identities/endpoints, Kueue Workloads, Ray/Trainer job pods | high-churn runtime objects; tracking them burns CPU and floods the UI |

```bash
./install.sh
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
kubectl -n argocd port-forward svc/argocd-server 8080:80
# UI: http://localhost:8080   user: admin
# CLI: argocd login localhost:8080 --insecure --username admin
```

Then bootstrap everything: `kubectl apply -f ../02-app-of-apps/root-app.yaml`.

Production notes: SSO via Keycloak (`configs.cm.oidc.config`), RBAC
(`configs.rbac`), HA (`redis-ha`, 2+ repo-server/controller replicas, controller
sharding when you manage many clusters), and notifications to Slack.

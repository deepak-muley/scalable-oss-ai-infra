#!/usr/bin/env bash
# Local equivalent of .github/workflows/lint.yaml.
#   brew install shellcheck yamllint kubeconform
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
FAIL=0

echo "== shellcheck"
# SC1090/1091: dynamic `source`; SC2046: ver_flag output is intentionally word-split
find . -name '*.sh' -not -path './.git/*' -print0 | \
  xargs -0 shellcheck -S warning -e SC1090,SC1091,SC2046 || FAIL=1

echo "== yamllint"
yamllint -c .yamllint.yaml . || FAIL=1

echo "== kubeconform (k8s manifests only; CRDs via the datree catalog)"
# Only files that look like Kubernetes objects; skip Helm values & templates.
# (portable to macOS bash 3.2: no mapfile)
grep -rlE '^kind: ' --include='*.yaml' . \
  | grep -vE '(values[^/]*\.yaml|/templates/|kind-config\.yaml|\.github/)' \
  | xargs kubeconform -strict -summary -ignore-missing-schemas \
      -schema-location default \
      -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
  || FAIL=1

exit $FAIL

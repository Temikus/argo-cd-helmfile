## Task automation for argo-cd-helmfile.
## Run `just` with no args to list recipes.

image := "argo-cd-helmfile:dev"
platform := "linux/amd64,linux/arm64"

# portable sha256 helper (sha256sum on Linux, shasum on macOS)
_sha256 := if `command -v sha256sum >/dev/null 2>&1 && echo yes || echo no` == "yes" { "sha256sum" } else { "shasum -a 256" }

# List available recipes
default:
    @just --list

# Build the image for the local arch and load it into Docker
build tag=image:
    docker buildx build --load -t {{tag}} .

# Build the full multi-arch image (no load; buildx cache only)
build-multiarch tag=image:
    docker buildx build --platform {{platform}} -t {{tag}} .

# Lint the Dockerfile with hadolint
lint:
    docker run --rm -i hadolint/hadolint hadolint - < Dockerfile

# Print helmfile version and assert the embedded vals has the Infisical provider
validate tag=image:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "## helmfile version"
    docker run --rm --entrypoint helmfile {{tag}} version | grep -i version | head -1
    echo "## vals infisical provider probe"
    tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
    mkdir -p "$tmp/chart/templates"
    printf 'apiVersion: v2\nname: probe\nversion: 0.1.0\n' > "$tmp/chart/Chart.yaml"
    printf 'apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: probe\ndata:\n  secret: {{{{ .Values.secret | quote }}}}\n' > "$tmp/chart/templates/cm.yaml"
    printf 'releases:\n  - name: probe\n    chart: ./chart\n    values:\n      - secret: ref+infisical://p?project=p&environment=dev&path=/&token=dummy\n' > "$tmp/helmfile.yaml"
    # The probe is expected to FAIL; we assert HOW it fails (auth error => provider
    # registered) rather than the "no provider registered for scheme" message.
    out="$(docker run --rm -v "$tmp:/wd" -w /wd --entrypoint helmfile {{tag}} template 2>&1 || true)"
    echo "$out" | tail -2
    if echo "$out" | grep -q 'no provider registered for scheme.*infisical'; then
      echo "FAIL: infisical provider NOT registered (vals too old)"; exit 1
    elif echo "$out" | grep -qi 'infisical'; then
      echo "PASS: infisical provider registered (reached auth/connection stage)"
    else
      echo "FAIL: unexpected output, infisical ref was not processed"; exit 1
    fi

# Recompute the pinned per-arch SHA256 for age and yq (no upstream checksum file)
update-checksums:
    #!/usr/bin/env bash
    set -euo pipefail
    ver() { sed -nE "s/^ARG $1=\"([^\"]+)\".*/\1/p" Dockerfile; }
    sha() { {{_sha256}} | awk '{print $1}'; }
    age_ver="$(ver AGE_VERSION)"; yq_ver="$(ver YQ_VERSION)"
    echo "# age ${age_ver}"
    for a in amd64 arm64; do
      h="$(curl -fsSL "https://github.com/FiloSottile/age/releases/download/${age_ver}/age-${age_ver}-linux-${a}.tar.gz" | sha)"
      printf '    %-6s) AGE_SHA="%s" ;;\n' "$a" "$h"
    done
    echo "# yq ${yq_ver}"
    for a in amd64 arm64; do
      h="$(curl -fsSL "https://github.com/mikefarah/yq/releases/download/${yq_ver}/yq_linux_${a}" | sha)"
      printf '    %-6s) YQ_SHA="%s" ;;\n' "$a" "$h"
    done

# Resolve each helm-plugin tag to the commit SHA to pin in the Dockerfile
update-plugin-shas:
    #!/usr/bin/env bash
    set -euo pipefail
    ver() { sed -nE "s/^ARG $1=\"([^\"]+)\".*/\1/p" Dockerfile; }
    resolve() { # repo tag arg-name
      sha="$(curl -fsSL "https://api.github.com/repos/$1/commits/$2" | sed -nE 's/^[[:space:]]*"sha":[[:space:]]*"([0-9a-f]{40})".*/\1/p' | head -1)"
      printf 'ARG %s="%s"\n' "$3" "$sha"
    }
    resolve databus23/helm-diff   "v$(ver HELM_DIFF_VERSION)"    HELM_DIFF_SHA
    resolve aslafy-z/helm-git      "v$(ver HELM_GIT_VERSION)"     HELM_GIT_SHA
    resolve jkroepke/helm-secrets  "v$(ver HELM_SECRETS_VERSION)" HELM_SECRETS_SHA

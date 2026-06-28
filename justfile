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

# Validate renovate.json. Pinned (not @latest) so a Renovate release that drops
# support for the local Node version can't silently break this; bump as needed.
renovate-validate:
    npx --yes --package renovate@43.245.0 -- renovate-config-validator --strict renovate.json

# Smoke-test the built image: print the version of each bundled tool
validate tag=image:
    #!/usr/bin/env bash
    set -euo pipefail
    docker run --rm --entrypoint helmfile {{tag}} version | grep -i version | head -1
    docker run --rm --entrypoint sops {{tag}} --version | head -1
    docker run --rm --entrypoint yq   {{tag}} --version
    docker run --rm --entrypoint age  {{tag}} --version
    docker run --rm --entrypoint helm-v3 {{tag}} version --short
    docker run --rm --entrypoint kubectl {{tag}} version --client=true 2>/dev/null | head -1

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

# Reads the latest vX.Y.Z tag, bumps the chosen segment, creates an annotated tag,
# and pushes it to origin. The tag push triggers CI (build+publish to GHCR) and the
# Release workflow (GitHub Release). Run only on a clean tree you intend to ship.
# Tag and push a release: just release [patch|minor|major] (default: patch)
release bump="patch":
    #!/usr/bin/env bash
    set -euo pipefail
    if [ -n "$(git status --porcelain)" ]; then
      echo "Working tree is dirty; commit or stash before releasing." >&2
      exit 1
    fi
    git fetch --tags origin
    latest=$(git tag -l 'v*' --sort=-v:refname | head -n1)
    [ -z "$latest" ] && latest="v0.0.0"
    IFS='.' read -r major minor patch <<< "${latest#v}"
    case "{{bump}}" in
      major) major=$((major + 1)); minor=0; patch=0 ;;
      minor) minor=$((minor + 1)); patch=0 ;;
      patch) patch=$((patch + 1)) ;;
      *) echo "Usage: just release [patch|minor|major]" >&2; exit 1 ;;
    esac
    new_tag="v${major}.${minor}.${patch}"
    if git rev-parse -q --verify "refs/tags/${new_tag}" >/dev/null; then
      echo "Tag ${new_tag} already exists." >&2
      exit 1
    fi
    echo "Tagging ${new_tag} (previous: ${latest})"
    git tag -a "${new_tag}" -m "Release ${new_tag}"
    git push origin "${new_tag}"
    echo "Released ${new_tag} -> https://github.com/Temikus/argo-cd-helmfile/releases/tag/${new_tag}"

# https://github.com/argoproj/argo-cd/blob/master/Dockerfile
#
# docker build --pull -t foobar .
# docker run --rm -ti             --entrypoint bash foobar
# docker run --rm -ti --user root --entrypoint bash foobar

ARG BASE_IMAGE=docker.io/library/ubuntu:24.04@sha256:786a8b558f7be160c6c8c4a54f9a57274f3b4fb1491cf65146521ae77ff1dc54

FROM $BASE_IMAGE

# Static image metadata. These are baked in so every build (including local
# `docker build`) carries them. CI additionally stamps the dynamic OCI labels
# (created, revision, version) via docker/metadata-action, which take precedence
# over the matching keys below. `maintainer` is the classic Docker label and is
# not emitted by metadata-action, so it only lives here. Keep
# org.opencontainers.image.base.digest in sync with the BASE_IMAGE ARG digest above.
LABEL maintainer="temikus (https://github.com/temikus)" \
      org.opencontainers.image.title="argo-cd-helmfile" \
      org.opencontainers.image.description="Argo CD ConfigManagementPlugin (CMP) sidecar that renders manifests with helmfile, bundled with helm, helmfile, kustomize, sops, age, kubeseal, kubectl and krew." \
      org.opencontainers.image.authors="Artem Yakimenko (https://github.com/temikus)" \
      org.opencontainers.image.vendor="temikus" \
      org.opencontainers.image.url="https://github.com/temikus/argo-cd-helmfile" \
      org.opencontainers.image.source="https://github.com/temikus/argo-cd-helmfile" \
      org.opencontainers.image.documentation="https://github.com/temikus/argo-cd-helmfile/blob/master/README.md" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.base.name="docker.io/library/ubuntu:24.04" \
      org.opencontainers.image.base.digest="sha256:786a8b558f7be160c6c8c4a54f9a57274f3b4fb1491cf65146521ae77ff1dc54"

# Fail RUN pipelines (the many `wget ... | tar` below) on the first failing
# command instead of masking a failed download with a succeeding tar.
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ENV ARGOCD_USER_ID=999

ARG TARGETPLATFORM
ARG BUILDPLATFORM

RUN echo "I am running on final $BUILDPLATFORM, building for $TARGETPLATFORM"

USER root

# DEBIAN_FRONTEND is scoped to this layer only (export), so it does not leak
# into the runtime image and affect later `apt` invocations by users.
RUN export DEBIAN_FRONTEND=noninteractive && \
  apt-get update && apt-get install --no-install-recommends -y \
  ca-certificates \
  git git-lfs \
  wget \
  jq && \
  apt-get clean && \
  rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

RUN groupadd -g $ARGOCD_USER_ID argocd && \
  useradd -r -l -u $ARGOCD_USER_ID -g argocd argocd && \
  mkdir -p /home/argocd && \
  chown argocd:0 /home/argocd && \
  chmod g=u /home/argocd

# aws
# https://www.educative.io/collection/page/6630002/6521965765984256/6553354502668288
#
#ARG INSTALL_AWS_TOOLS
#RUN apt-get update && apt-get install --no-install-recommends -y \
#    awscli \
#    && \
#    apt-get clean && \
#    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# az cli
# https://learn.microsoft.com/en-us/cli/azure/install-azure-cli-linux?pivots=apt
#
#ARG INSTALL_AZURE_TOOLS
#RUN apt-get update && apt-get install --no-install-recommends -y \
#    ca-certificates curl apt-transport-https lsb-release gnupg \
#    && \
#    mkdir -p /etc/apt/keyrings && \
#    curl -sLS https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | tee /etc/apt/keyrings/microsoft.gpg > /dev/null && \
#    chmod go+r /etc/apt/keyrings/microsoft.gpg && \
#    AZ_REPO=$(lsb_release -cs) && \
#    echo "deb [arch=`dpkg --print-architecture` signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/azure-cli/ $AZ_REPO main" | tee /etc/apt/sources.list.d/azure-cli.list && \
#    apt-get update && apt-get install --no-install-recommends -y \
#    azure-cli && \
#    apt-get clean && \
#    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*


# gcloud cli
# https://cloud.google.com/sdk/docs/install#deb
#
#ARG INSTALL_GCLOUD_TOOLS
#RUN apt-get update && apt-get install --no-install-recommends -y \
#    apt-transport-https ca-certificates gnupg \
#    && \
#    echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | tee -a /etc/apt/sources.list.d/google-cloud-sdk.list && \
#    curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key --keyring /usr/share/keyrings/cloud.google.gpg add - && \
#    apt-get update && apt-get install --no-install-recommends -y \
#    google-cloud-cli && \
#    apt-get clean && \
#    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# binary versions. The `# renovate:` lines let Renovate bump each pin (see
# renovate.json); they must sit immediately above their ARG.
# https://github.com/FiloSottile/age/releases
# renovate: datasource=github-releases depName=FiloSottile/age
ARG AGE_VERSION="v1.3.1"
# install via apt for now
#ARG JQ_VERSION="1.6"
# https://github.com/helm/helm/releases (kept on v3.x; helmfile drives helm3, v4 is a breaking major)
# renovate: datasource=github-releases depName=helm/helm
ARG HELM3_VERSION="v3.21.2"
# https://github.com/helmfile/helmfile/releases
# renovate: datasource=github-releases depName=helmfile/helmfile
ARG HELMFILE_VERSION="1.6.0"
# https://github.com/kubernetes-sigs/kustomize/releases
# renovate: datasource=github-releases depName=kubernetes-sigs/kustomize extractVersion=^kustomize/v(?<version>.+)$
ARG KUSTOMIZE5_VERSION="5.8.1"
# https://github.com/getsops/sops/releases
# renovate: datasource=github-releases depName=getsops/sops
ARG SOPS_VERSION="v3.13.1"
# https://github.com/mikefarah/yq/releases
# renovate: datasource=github-releases depName=mikefarah/yq
ARG YQ_VERSION="v4.53.3"

# relevant for kubectl if installed
# renovate: datasource=github-releases depName=bitnami-labs/sealed-secrets
ARG KUBESEAL_VERSION="0.38.1"
# curl -v -L 'https://dl.k8s.io/release/stable.txt'
# renovate: datasource=github-releases depName=kubernetes/kubernetes
ARG KUBECTL_VERSION="v1.36.2"
# https://github.com/kubernetes-sigs/krew/releases/
# renovate: datasource=github-releases depName=kubernetes-sigs/krew
ARG KREW_VERSION="v0.5.0"

# Each binary is downloaded then verified against its publisher's SHA256 before
# install. Most publish a checksum file we fetch at build time; age and yq do
# not publish a usable one, so their per-arch hashes are pinned here directly.
# When bumping AGE_VERSION / YQ_VERSION, regenerate these with
# `just update-checksums` and paste the printed values into the case blocks.
# wget -qO "/usr/local/bin/jq"       "https://github.com/stedolan/jq/releases/download/jq-${JQ_VERSION}/jq-linux64" && \
WORKDIR /tmp
RUN \
  GO_ARCH=$(uname -m | sed -e 's/x86_64/amd64/' -e 's/\(arm\)\(64\)\?.*/\1\2/' -e 's/aarch64$/arm64/') && \
  # helm v3 -- upstream .sha256sum (full "<hash>  <file>" line)
  HELM_TGZ="helm-${HELM3_VERSION}-linux-${GO_ARCH}.tar.gz" && \
  wget -qO "${HELM_TGZ}" "https://get.helm.sh/${HELM_TGZ}" && \
  wget -qO- "https://get.helm.sh/${HELM_TGZ}.sha256sum" | sha256sum -c - && \
  tar zxf "${HELM_TGZ}" --strip-components=1 -C /tmp "linux-${GO_ARCH}/helm" && mv /tmp/helm /usr/local/bin/helm-v3 && \
  # sops -- upstream checksums.txt (list)
  SOPS_BIN="sops-${SOPS_VERSION}.linux.${GO_ARCH}" && \
  wget -qO "${SOPS_BIN}" "https://github.com/getsops/sops/releases/download/${SOPS_VERSION}/${SOPS_BIN}" && \
  wget -qO- "https://github.com/getsops/sops/releases/download/${SOPS_VERSION}/sops-${SOPS_VERSION}.checksums.txt" | grep " ${SOPS_BIN}$" | sha256sum -c - && \
  install -m 0755 "${SOPS_BIN}" /usr/local/bin/sops && \
  # age -- no upstream checksum file; pinned per-arch hash
  AGE_TGZ="age-${AGE_VERSION}-linux-${GO_ARCH}.tar.gz" && \
  wget -qO "${AGE_TGZ}" "https://github.com/FiloSottile/age/releases/download/${AGE_VERSION}/${AGE_TGZ}" && \
  case "${GO_ARCH}" in \
    amd64) AGE_SHA="bdc69c09cbdd6cf8b1f333d372a1f58247b3a33146406333e30c0f26e8f51377" ;; \
    arm64) AGE_SHA="c6878a324421b69e3e20b00ba17c04bc5c6dab0030cfe55bf8f68fa8d9e9093a" ;; \
    *) echo "no pinned age sha for ${GO_ARCH}" >&2; exit 1 ;; \
  esac && \
  echo "${AGE_SHA}  ${AGE_TGZ}" | sha256sum -c - && \
  tar zxf "${AGE_TGZ}" --strip-components=1 -C /usr/local/bin age/age age/age-keygen && \
  # helmfile -- upstream checksums.txt (list)
  HELMFILE_TGZ="helmfile_${HELMFILE_VERSION}_linux_${GO_ARCH}.tar.gz" && \
  wget -qO "${HELMFILE_TGZ}" "https://github.com/helmfile/helmfile/releases/download/v${HELMFILE_VERSION}/${HELMFILE_TGZ}" && \
  wget -qO- "https://github.com/helmfile/helmfile/releases/download/v${HELMFILE_VERSION}/helmfile_${HELMFILE_VERSION}_checksums.txt" | grep " ${HELMFILE_TGZ}$" | sha256sum -c - && \
  tar zxf "${HELMFILE_TGZ}" -C /usr/local/bin helmfile && \
  # yq -- upstream checksum format is awkward; pinned per-arch hash
  wget -qO "yq" "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_${GO_ARCH}" && \
  case "${GO_ARCH}" in \
    amd64) YQ_SHA="fa52a4e758c63d38299163fbdd1edfb4c4963247918bf9c1c5d31d84789eded4" ;; \
    arm64) YQ_SHA="578648e463a11c1b6db6010cbf41eafed6bee79466fcffa1bb446672cf7945ea" ;; \
    *) echo "no pinned yq sha for ${GO_ARCH}" >&2; exit 1 ;; \
  esac && \
  echo "${YQ_SHA}  yq" | sha256sum -c - && \
  install -m 0755 "yq" /usr/local/bin/yq && \
  # kubectl -- upstream .sha256 (hash only)
  wget -qO "kubectl" "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${GO_ARCH}/kubectl" && \
  echo "$(wget -qO- "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${GO_ARCH}/kubectl.sha256" | tr -d '[:space:]')  kubectl" | sha256sum -c - && \
  install -m 0755 "kubectl" /usr/local/bin/kubectl && \
  # krew -- upstream .sha256 (hash only)
  KREW_TGZ="krew-linux_${GO_ARCH}.tar.gz" && \
  wget -qO "${KREW_TGZ}" "https://github.com/kubernetes-sigs/krew/releases/download/${KREW_VERSION}/${KREW_TGZ}" && \
  echo "$(wget -qO- "https://github.com/kubernetes-sigs/krew/releases/download/${KREW_VERSION}/${KREW_TGZ}.sha256" | tr -d '[:space:]')  ${KREW_TGZ}" | sha256sum -c - && \
  tar zxf "${KREW_TGZ}" "./krew-linux_${GO_ARCH}" && mv "./krew-linux_${GO_ARCH}" /usr/local/bin/kubectl-krew && \
  # kubeseal -- upstream checksums.txt (list)
  KUBESEAL_TGZ="kubeseal-${KUBESEAL_VERSION}-linux-${GO_ARCH}.tar.gz" && \
  wget -qO "${KUBESEAL_TGZ}" "https://github.com/bitnami-labs/sealed-secrets/releases/download/v${KUBESEAL_VERSION}/${KUBESEAL_TGZ}" && \
  wget -qO- "https://github.com/bitnami-labs/sealed-secrets/releases/download/v${KUBESEAL_VERSION}/sealed-secrets_${KUBESEAL_VERSION}_checksums.txt" | grep " ${KUBESEAL_TGZ}$" | sha256sum -c - && \
  tar zxf "${KUBESEAL_TGZ}" -C /usr/local/bin kubeseal && \
  # kustomize -- upstream checksums.txt (list)
  KUSTOMIZE_TGZ="kustomize_v${KUSTOMIZE5_VERSION}_linux_${GO_ARCH}.tar.gz" && \
  wget -qO "${KUSTOMIZE_TGZ}" "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv${KUSTOMIZE5_VERSION}/${KUSTOMIZE_TGZ}" && \
  wget -qO- "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv${KUSTOMIZE5_VERSION}/checksums.txt" | grep " ${KUSTOMIZE_TGZ}$" | sha256sum -c - && \
  tar zxf "${KUSTOMIZE_TGZ}" -C /usr/local/bin kustomize && \
  rm -f /tmp/helm-* /tmp/sops-* /tmp/age-* /tmp/helmfile_* /tmp/yq /tmp/kubectl /tmp/krew-* /tmp/kubeseal-* /tmp/kustomize_* && \
  true

COPY src/*.sh /usr/local/bin/

RUN \
  ln -sf /usr/local/bin/helm-v3 /usr/local/bin/helm && \
  chown root:root /usr/local/bin/* && chmod 755 /usr/local/bin/*

ENV USER=argocd
USER $ARGOCD_USER_ID

WORKDIR /home/argocd/cmp-server/config/
COPY plugin.yaml ./
WORKDIR /home/argocd

# repo-server containers use /helm-working-dir (empty dir volume helm-working-dir)
#
# HELM_CACHE_HOME=/helm-working-dir
# HELM_CONFIG_HOME=/helm-working-dir
# HELM_DATA_HOME=/helm-working-dir
#
ENV HELM_CACHE_HOME=/home/argocd/helm/cache
#ENV HELM_CONFIG_HOME=/home/argocd/helm/config
ENV HELM_DATA_HOME=/home/argocd/helm/data
ENV KREW_ROOT=/home/argocd/krew
ENV PATH="${KREW_ROOT}/bin:$PATH"

# plugin versions. Each *_SHA is the commit its tag points to; the build clones
# the tag and aborts if the tag has been moved off that commit (tags are
# mutable, commits are not). Regenerate with `just update-plugin-shas` when
# bumping a version. (helm-diff additionally pulls a prebuilt binary in its own
# install hook, which remains version-pinned and upstream-controlled.)
# https://github.com/databus23/helm-diff/releases
# renovate: datasource=github-tags depName=databus23/helm-diff
ARG HELM_DIFF_VERSION="3.15.10"
ARG HELM_DIFF_SHA="5873f8d94712f014dc2bb329acae63b8ffbf569b"
# https://github.com/aslafy-z/helm-git/releases
# renovate: datasource=github-tags depName=aslafy-z/helm-git
ARG HELM_GIT_VERSION="1.5.2"
ARG HELM_GIT_SHA="8f910e377bf743cc07ce963a696b1e7929aebb80"
# https://github.com/jkroepke/helm-secrets/releases
# renovate: datasource=github-tags depName=jkroepke/helm-secrets
ARG HELM_SECRETS_VERSION="4.7.7"
ARG HELM_SECRETS_SHA="f02f8df1c57af3c65f531bb0e0bc0859a8540845"

RUN \
  install_helm_plugin() { \
    local repo="$1" ref="$2" want="$3" dir got rc; \
    dir="$(mktemp -d)"; \
    git clone --depth 1 --branch "${ref}" "${repo}" "${dir}" || return 1; \
    got="$(git -C "${dir}" rev-parse HEAD)"; \
    if [ "${got}" != "${want}" ]; then \
      echo "ERROR: ${repo} ${ref} resolved to ${got}, expected ${want}" >&2; rm -rf "${dir}"; return 1; \
    fi; \
    helm-v3 plugin install "${dir}"; rc=$?; rm -rf "${dir}"; return ${rc}; \
  } && \
  install_helm_plugin https://github.com/databus23/helm-diff   "v${HELM_DIFF_VERSION}"    "${HELM_DIFF_SHA}" && \
  install_helm_plugin https://github.com/aslafy-z/helm-git     "v${HELM_GIT_VERSION}"     "${HELM_GIT_SHA}" && \
  install_helm_plugin https://github.com/jkroepke/helm-secrets "v${HELM_SECRETS_VERSION}" "${HELM_SECRETS_SHA}" && \
  kubectl krew update && \
  mkdir -p ${KREW_ROOT}/bin && \
  true

# array is exec form, string is shell form
# this binary in injected via a shared folder with the repo server
#ENTRYPOINT [/var/run/argocd/argocd-cmp-server]

# syntax=docker/dockerfile:1.4

#
# builder arguments: BASE_IMAGE
#
# base image (FROM) may not be triggered "on-build" of target images
#
# as such, the base image must be pre-built and specified in the build of the builder
#
ARG BASE_IMAGE=python:3.11-bookworm

FROM ${BASE_IMAGE}

#
# required on-build arguments
#
ONBUILD ARG APP_NAME
ONBUILD ARG ORG_NAME
ONBUILD ARG APP_VERSION
#
# APP_URL: optional: override default construction of app bundle url (using above)
#
ONBUILD ARG APP_URL=

#
# on-build labels
#
ONBUILD LABEL org.opencontainers.image.ref.name=${APP_NAME}
ONBUILD LABEL org.opencontainers.image.vendor=${ORG_NAME}
ONBUILD LABEL org.opencontainers.image.version=${APP_VERSION}

#
# builder labels
#
# re-declare BASE_IMAGE post-FROM s.t. accessible to label
ARG BASE_IMAGE
LABEL org.opencontainers.image.base.name=${BASE_IMAGE}

#
# builder build execution
#
RUN <<PKG-CONF
#!/usr/bin/bash
set -euo pipefail

# ensure apt caching configuration for (future) PKG-INSTALL stanza(s)
rm -f /etc/apt/apt.conf.d/docker-clean

cat << KEEP-CACHE > /etc/apt/apt.conf.d/keep-cache
Binary::apt::APT::Keep-Downloaded-Packages "true";
KEEP-CACHE
PKG-CONF

#
# on-build execution
#
# ensure app image base system is up-to-date and includes basic dependencie(s)
#
ONBUILD RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
            --mount=type=cache,target=/var/lib/apt,sharing=locked <<PKG-INSTALL
#!/usr/bin/bash
export DEBIAN_FRONTEND=noninteractive

set -euo pipefail

apt update

apt upgrade --yes

# curl is provided by most bases but not by slim
# ca-certificates is provided by all debian but not ubuntu
apt install --yes --no-install-recommends curl ca-certificates

# python is not provided by all bases
# make conditional as bases don't necessarily use package manager
if ! command -v python3 > /dev/null; then
  apt install --yes --no-install-recommends python3
fi
PKG-INSTALL
#
# install fate (or fate-like) app
#
ONBUILD RUN <<APP
#!/usr/bin/bash
set -euo pipefail

if [ -z "${APP_URL}" ]; then
  ARCH="$(arch)"

  if [[ ! -v PYTHON_VERSION ]]; then
    PYTHON_VERSION="$(python3 --version | awk '{print $2}')"
  fi

  # strip patch version
  PY_VERSION="${PYTHON_VERSION%.*}"
  # strip periods
  PY_VERSION="${PY_VERSION//./}"

  CURL_TARGET="https://github.com/${ORG_NAME}/${APP_NAME}/releases/download/${APP_VERSION}/${APP_NAME}-all-${APP_VERSION}-py${PY_VERSION}-${ARCH}.tar"
else
  CURL_TARGET="${APP_URL}"
fi

curl --silent --location --fail-with-body "${CURL_TARGET}" | tar -xf - -C /usr/local/bin/

#
# the app's pre-built executables are now installed
#
# still, it's useful to run the bundle-extracted app at least once s.t. it caches itself on the filesystem
# (this eliminates first-run overhead and ensures the filesystem needn't be written to during any such initial bootstrapping)
#
# we *won't* install the bash completion package; but, we'll set up the app to support this if it is installed
#
${APP_NAME} init comp --shell=bash

# the root user can only take advantage of bash completion -- presuming it is installed -- if we add the below
cat << BASH-COMP >> /root/.bashrc
if [ -f /etc/bash_completion ] && ! shopt -oq posix; then
  . /etc/bash_completion
fi
BASH-COMP
APP

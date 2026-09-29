#!/usr/bin/env bash

# .buildkite/libs/common.sh
#
# Shared values and helpers for the pipeline generator, hooks and step scripts.
# Source with a BASH_SOURCE-relative path so it works regardless of CWD:
#   source "$(dirname "${BASH_SOURCE[0]}")/libs/common.sh"        # from .buildkite/
#   source "$(dirname "${BASH_SOURCE[0]}")/../libs/common.sh"     # from .buildkite/hooks/ and .buildkite/steps/
#
# The variables set here and by resolve_image() are read by the sourcing files, which shellcheck can't see when
# linting this file in isolation.
# shellcheck disable=SC2034

REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GITHUB_REPOSITORY="antilax-3/docker-unbound"
DOCKER_REPOSITORY="antilax3/unbound"
REGISTRY="docker.io"
# Platforms every image is built for, by the short name used in test step keys and labels. armv7 is absent because
# antilax3/wolfi, like the wolfi-base image beneath it, publishes amd64 and arm64 only.
PLATFORMS="amd64 arm64"
# Base images every variant is built on, in tag order. The first is the default variant and takes the unsuffixed
# tags; the others take a tag suffix of their own name, following the docker-library convention.
VARIANTS="wolfi alpine"
DEFAULT_VARIANT="wolfi"

DOCKERFILE="${REPOSITORY_ROOT}/Dockerfile"
# The unbound release, e.g. 1.26.1, from the Dockerfile's UNBOUND_VERSION build arg, and its series (1.26) and major
# version (1).
UNBOUND_RELEASE=$(sed -nE 's/^ARG UNBOUND_VERSION="([0-9]+\.[0-9]+\.[0-9]+)"$/\1/p' "${DOCKERFILE}")
UNBOUND_SERIES="${UNBOUND_RELEASE%.*}"
UNBOUND_MAJOR="${UNBOUND_RELEASE%%.*}"

# Test jobs keyed "test-<variant>-<platform>" get both from the step key, so steps don't each need them in env.
# Neither a variant nor a platform name contains a dash, so the split is unambiguous.
if [[ "${BUILDKITE_STEP_KEY:-}" == test-* ]]; then
  STEP_TARGET="${BUILDKITE_STEP_KEY#test-}"
  VARIANT="${STEP_TARGET%%-*}"
  PLATFORM="${STEP_TARGET#*-}"
fi

# Prints the base image a variant is built on.
variant_base() {
  case "${1}" in
    wolfi) echo "antilax3/wolfi:latest" ;;
    alpine) echo "antilax3/alpine:latest" ;;
  esac
}

# Prints the tag suffix a variant's tags carry, empty for the default variant.
variant_suffix() {
  if [[ "${1}" == "${DEFAULT_VARIANT}" ]]; then
    echo ""
  else
    echo "-${1}"
  fi
}

# Prints the Docker platform for a short platform name, e.g. armv7 -> linux/arm/v7.
docker_platform() {
  case "${1}" in
    amd64) echo "linux/amd64" ;;
    arm64) echo "linux/arm64" ;;
    armv7) echo "linux/arm/v7" ;;
  esac
}

# Returns success for pushes to master, the only builds that publish the latest and version tags.
master() {
  [[ "${BUILDKITE_BRANCH}" == "master" ]] && [[ "${BUILDKITE_PULL_REQUEST}" == "false" ]]
}

# Makes a branch name safe to use in a Docker tag.
sanitize_tag() {
  echo "${1}" | sed -E 's/[^A-Za-z0-9_.-]+/-/g'
}

# Resolves the image details for the build. Sets as globals:
#   BUILD_TAG - the build-scoped tag, e.g. BK12, also used as the version label/build arg
#   IMAGE     - the fully qualified build-scoped image the test step pulls
#   TAGS      - the tags pushed for the build context, following antilax-3/docker-baseimage-alpine:
#                 local branch -> <branch> with unsafe characters replaced, e.g. renovate/unbound-1.x -> renovate-unbound-1.x
#                 fork PRs     -> PR<number> (Buildkite prefixes fork branch names with owner:)
#                 master       -> latest, <major>, <series> and <release>, e.g. latest 1 1.26 1.26.1
#               and always BK<build>
#
# Every tag of a non-default variant carries that variant's suffix, except the one standing in for latest, which is
# the bare variant name: the alpine variant of the above is alpine, 1-alpine, 1.26-alpine, 1.26.1-alpine.
#
# $1 - the variant, defaulting to DEFAULT_VARIANT
resolve_image() {
  local variant="${1:-${DEFAULT_VARIANT}}" suffix
  suffix="$(variant_suffix "${variant}")"

  BUILD_TAG="BK${BUILDKITE_BUILD_NUMBER}${suffix}"
  IMAGE="${REGISTRY}/${DOCKER_REPOSITORY}:${BUILD_TAG}"
  TAGS=""

  if [[ "${BUILDKITE_BRANCH}" != "master" ]] && [[ ! "${BUILDKITE_BRANCH}" =~ .*:.* ]]; then
    TAGS="$(sanitize_tag "${BUILDKITE_BRANCH}")${suffix}"
  elif [[ "${BUILDKITE_BRANCH}" =~ .*:.* ]]; then
    TAGS="PR${BUILDKITE_PULL_REQUEST}${suffix}"
  elif master; then
    TAGS="${suffix:-latest} ${UNBOUND_MAJOR}${suffix} ${UNBOUND_SERIES}${suffix} ${UNBOUND_RELEASE}${suffix}"
    TAGS="${TAGS#-}"
  fi

  TAGS+=" ${BUILD_TAG}"
}

# Resolves IMAGE (see resolve_image) to the manifest for one platform. Sets as globals:
#   DOCKER_PLATFORM - the Docker platform, e.g. linux/arm/v7
#   PLATFORM_IMAGE  - IMAGE pinned to that platform's manifest digest; tests of different platforms can share a
#                     Docker daemon, and pulling the multi-platform tag for each would race over the local tag.
#
# The pre-command hook exports both, so the command and later hooks reuse them instead of querying the registry again.
# Registry lookups are retried, as Docker Hub intermittently fails token requests. Returns non-zero if no digest resolves.
#
# $1 - the short platform name, e.g. armv7
resolve_platform_image() {
  local attempt digest

  DOCKER_PLATFORM=$(docker_platform "${1}")

  if [[ "${PLATFORM_IMAGE:-}" == "${IMAGE%:*}@sha256:"* ]]; then
    return 0
  fi

  for attempt in 1 2 3 4 5; do
    digest=$(docker buildx imagetools inspect "${IMAGE}" --format '{{json .Manifest}}' | jq -r --arg platform "${DOCKER_PLATFORM}" \
      '.manifests[] | select((.platform.os + "/" + .platform.architecture + (if .platform.variant then "/" + .platform.variant else "" end)) == $platform) | .digest')

    if [[ "${digest}" =~ ^sha256:[0-9a-f]{64}$ ]]; then
      PLATFORM_IMAGE="${IMAGE%:*}@${digest}"
      return 0
    fi

    [[ ${attempt} -lt 5 ]] && echo "Unable to resolve the ${DOCKER_PLATFORM} digest of ${IMAGE}, retrying (${attempt}/5)" >&2 && sleep $((attempt * 5))
  done

  echo "Unable to resolve the ${DOCKER_PLATFORM} digest of ${IMAGE}" >&2
  PLATFORM_IMAGE=""
  return 1
}

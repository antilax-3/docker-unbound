#!/usr/bin/env bash
set -u

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/../libs/common.sh"

resolve_image "${VARIANT}"
resolve_platform_image "${PLATFORM}" || exit 1

case "${PLATFORM}" in
  amd64) APK_ARCH="x86_64"; ELF_MACHINE="62" ;;
  arm64) APK_ARCH="aarch64"; ELF_MACHINE="183" ;;
  armv7) APK_ARCH="armv7"; ELF_MACHINE="40" ;;
esac

# The user database is read out of /etc/passwd rather than through getent, which not every base ships.
case "${VARIANT}" in
  alpine)
    OS_ID="alpine"; LIBC="musl"; INTERPRETER="/lib/ld-musl-*"
    RUNTIME_PACKAGES="bind-tools dnssec-root"
    BUILD_PACKAGES="clang curl expat-dev gcc gnupg hiredis-dev libevent-dev lld llvm make musl-dev nghttp2-dev openssl-dev"
    BUILD_PACKAGES+=" pkgconf protobuf-c-compiler protobuf-c-dev"
    ;;
esac

REVISION="${BUILDKITE_COMMIT}"
# The binaries unbound installs, all built from source rather than taken from the base's unbound package.
UNBOUND_BINARIES="unbound unbound-anchor unbound-checkconf unbound-control unbound-host"
VOLUME="unbound-test-${BUILDKITE_BUILD_NUMBER}-${VARIANT}-${PLATFORM}"
MARKER="__TEST_OUTPUT__"
FAILURES=0

# Runs a shell script inside the container through /init and with-contenv, the same way the
# image's services run, and returns only the script's output (not the s6 startup banner, nor the
# log lines unbound writes to the same stdout).
run() {
  local options="$1" script="$2"
  # shellcheck disable=SC2086 # options holds multiple docker run flags and must be word split.
  docker run --rm --platform "${DOCKER_PLATFORM}" ${options} "${PLATFORM_IMAGE}" /command/with-contenv sh -c "echo ${MARKER}; ${script}" 2> /dev/null | sed "1,/^${MARKER}\$/d" | grep -vE '^\[[0-9]+\] unbound\[[0-9]+:[0-9]+\] '
}

check() {
  local description="$1" expected="$2" actual="$3"

  if [[ "${actual}" == "${expected}" ]]; then
    echo "ok - ${description}"
  else
    echo "not ok - ${description}"
    echo "    expected: ${expected}"
    echo "    actual:   ${actual}"
    FAILURES=$((FAILURES + 1))
  fi
}

# Prints a script that queries the unbound service into /tmp/dig once it answers, retrying while it starts and primes
# its cache from the root servers.
query() {
  echo "for i in \$(seq 1 30); do dig +time=2 +tries=1 @127.0.0.1 ${1} > /tmp/dig 2>&1 && grep -q 'status: ' /tmp/dig && break; sleep 1; done"
}

echo "--- :label: Image metadata [${DOCKER_PLATFORM}]"
check "image platform is ${DOCKER_PLATFORM}" "${DOCKER_PLATFORM}" \
  "$(docker image inspect -f '{{.Os}}/{{.Architecture}}{{with .Variant}}/{{.}}{{end}}' "${PLATFORM_IMAGE}" | sed 's|^linux/arm64/v8$|linux/arm64|')"
check "entrypoint is /init" '["/init"]' "$(docker image inspect -f '{{json .Config.Entrypoint}}' "${PLATFORM_IMAGE}")"
check "version label is ${BUILD_TAG}" "${BUILD_TAG}" "$(docker image inspect -f '{{index .Config.Labels "version"}}' "${PLATFORM_IMAGE}")"
check "build_date label is set" "set" "$(docker image inspect -f '{{with index .Config.Labels "build_date"}}set{{end}}' "${PLATFORM_IMAGE}")"
check "OCI revision label is ${REVISION}" "${REVISION}" "$(docker image inspect -f '{{index .Config.Labels "org.opencontainers.image.revision"}}' "${PLATFORM_IMAGE}")"
check "OCI source label is the GitHub repository" "https://github.com/${GITHUB_REPOSITORY}" \
  "$(docker image inspect -f '{{index .Config.Labels "org.opencontainers.image.source"}}' "${PLATFORM_IMAGE}")"
check "OCI version label is ${BUILD_TAG}" "${BUILD_TAG}" "$(docker image inspect -f '{{index .Config.Labels "org.opencontainers.image.version"}}' "${PLATFORM_IMAGE}")"
check "OCI created label is an RFC 3339 timestamp" "valid" \
  "$(docker image inspect -f '{{index .Config.Labels "org.opencontainers.image.created"}}' "${PLATFORM_IMAGE}" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' && echo valid)"

echo "--- :package: Inherited base image [${VARIANT}]"
check "base is ${OS_ID}" "${OS_ID}" "$(run "" ". /etc/os-release; echo \${ID}")"
check "apk architecture is ${APK_ARCH}" "${APK_ARCH}" "$(run "" "apk --print-arch")"
check "libc is ${LIBC}" "found" "$(run "" "ls ${INTERPRETER} > /dev/null 2>&1 && echo found")"
check "abc passwd entry" "abc:911:911:/config:/bin/false" \
  "$(run "" "grep '^abc:' /etc/passwd | cut -d: -f1,3,4,6,7")"
check "abc is in the users group" "yes" "$(run "" "id -nG abc | tr ' ' '\\n' | grep -qx users && echo yes")"
check "container keeps s6 supervision" "0" "$(docker run --rm --platform "${DOCKER_PLATFORM}" "${PLATFORM_IMAGE}" true > /dev/null 2>&1; echo $?)"
check "s6-overlay starts without deprecation warnings" "" \
  "$(docker run --rm --platform "${DOCKER_PLATFORM}" "${PLATFORM_IMAGE}" true 2>&1 | grep -i 'deprecated')"

echo "--- :globe_with_meridians: Unbound ${UNBOUND_RELEASE}"
check "unbound version is ${UNBOUND_RELEASE}" "Version ${UNBOUND_RELEASE}" "$(run "" "unbound -V | head -n1")"
check "unbound is built for ${APK_ARCH}" "${ELF_MACHINE}" "$(run "" "od -An -tu2 -j18 -N2 /usr/sbin/unbound" | xargs)"
check "every unbound binary runs" "${UNBOUND_BINARIES}" \
  "$(run "" "for b in ${UNBOUND_BINARIES}; do \${b} -h > /dev/null 2>&1; [ \$? -le 1 ] && echo \${b}; done" | xargs)"
check "every shared library unbound links resolves" "" \
  "$(run "" "for b in ${UNBOUND_BINARIES}; do ldd /usr/sbin/\${b} 2>&1 | grep -i 'not found'; done")"
check "unbound links the dns64, cachedb, subnet and respip modules" "dns64 cachedb subnetcache respip validator iterator" \
  "$(run "" "unbound -V | sed -n 's/^Linked modules: //p'")"
check "unbound is built with dnstap" "yes" \
  "$(run "" "printf 'server:\\ndnstap:\\n  dnstap-enable: yes\\n' > /tmp/dnstap.conf; unbound-checkconf -o dnstap-enable /tmp/dnstap.conf")"
check "ports 53/tcp and 53/udp are exposed" '{"53/tcp":{},"53/udp":{}}' \
  "$(docker image inspect -f '{{json .Config.ExposedPorts}}' "${PLATFORM_IMAGE}")"
check "/config is a volume" '{"/config":{}}' "$(docker image inspect -f '{{json .Config.Volumes}}' "${PLATFORM_IMAGE}")"
check "healthcheck queries the service" '["CMD-SHELL","dig @127.0.0.1 || exit 1"]' \
  "$(docker image inspect -f '{{json .Config.Healthcheck.Test}}' "${PLATFORM_IMAGE}")"
check "root hints are present" "found" "$(run "" "grep -q 'A.ROOT-SERVERS.NET' /etc/unbound/root.hints && echo found")"
check "config and trust anchor are copied to /config, owned by abc" "abc:abc trusted-key.key abc:abc unbound.conf" \
  "$(run "" "cd /config && stat -c '%U:%G %n' trusted-key.key unbound.conf" | xargs)"
check "trust anchor is read from /config" "/config/trusted-key.key" \
  "$(run "" "unbound-checkconf -o auto-trust-anchor-file /config/unbound.conf")"
check "unbound service runs as abc" "abc" \
  "$(run "" "for i in \$(seq 1 20); do for p in /proc/[0-9]*; do [ \"\$(cat \${p}/comm 2> /dev/null)\" = unbound ] && stat -c %U \${p} && exit; done; sleep 0.5; done")"
check "unbound resolves and validates a signed zone" "NOERROR ad" \
  "$(run "" "$(query nlnetlabs.nl); sed -nE 's/.*status: ([A-Z]+),.*/\\1/p; s/.*flags:[a-z ]* (ad)[ ;].*/\\1/p' /tmp/dig" | xargs)"
check "unbound rejects a zone with a broken signature" "SERVFAIL" \
  "$(run "" "$(query dnssec-failed.org); sed -nE 's/.*status: ([A-Z]+),.*/\\1/p' /tmp/dig")"
check "unbound stays up once it has updated its trust anchor" "1" \
  "$(run "" "$(query nlnetlabs.nl); sleep 5; for p in /proc/[0-9]*; do cat \${p}/comm 2> /dev/null; done | grep -c '^unbound$'")"

echo "--- :floppy_disk: Existing configuration"
docker volume create "${VOLUME}" > /dev/null
# Recreate a /config written by earlier images, whose default config pointed unbound at the packaged trust anchor.
run "-v ${VOLUME}:/config" "sed -i 's|/config/trusted-key.key|/usr/share/dnssec-root/trusted-key.key|' /config/unbound.conf; rm /config/trusted-key.key" > /dev/null
check "a config left pointing at the packaged trust anchor is moved to /config" "/config/trusted-key.key abc" \
  "$(run "-v ${VOLUME}:/config" "unbound-checkconf -o auto-trust-anchor-file /config/unbound.conf; stat -c %U /config/trusted-key.key" | xargs)"
run "-v ${VOLUME}:/config" "printf '\\n  # kept\\n' >> /config/unbound.conf" > /dev/null
check "an existing config is not overwritten" "  # kept" "$(run "-v ${VOLUME}:/config" "tail -n1 /config/unbound.conf")"
docker volume rm "${VOLUME}" > /dev/null

echo "--- :package: Packages"
check "unbound is not installed from the base's packages" "" "$(run "" "apk info -e unbound unbound-libs" | xargs)"
check "runtime packages are installed" "${RUNTIME_PACKAGES}" \
  "$(run "" "for p in ${RUNTIME_PACKAGES}; do apk info -e \${p}; done" | xargs)"
check "build dependencies are removed" "" \
  "$(run "" "for p in build-dependencies ${BUILD_PACKAGES}; do apk info -e \${p}; done" | xargs)"
check "no build artefacts are left behind" "" "$(run "" "ls -d /tmp/* 2> /dev/null" | xargs)"

if [[ ${FAILURES} -gt 0 ]]; then
  echo "^^^ +++"
  echo "${FAILURES} check(s) failed"
  exit 1
fi

echo "All checks passed"

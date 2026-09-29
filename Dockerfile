# syntax=docker/dockerfile:1
ARG BASE_IMAGE="antilax3/alpine:latest"

# set unbound version
# renovate: datasource=github-releases depName=unbound packageName=NLnetLabs/unbound
ARG UNBOUND_VERSION="1.26.1"

FROM --platform=${BUILDPLATFORM} ${BASE_IMAGE} AS build

ARG TARGETARCH
ARG UNBOUND_VERSION

SHELL ["/bin/ash", "-euo", "pipefail", "-c"]

RUN <<'EOF'
set -euo pipefail

# the key nlnet labs signs its release tarballs with, as listed on https://nlnetlabs.nl/signing-keys/
UNBOUND_KEY="231018690C4D903EF419146AA144323DEAACDF45"

recv_key() {
  local key="${1}" keyserver

  for keyserver in keys.openpgp.org keyserver.ubuntu.com; do
    gpg --batch --keyserver "${keyserver}" --recv-keys "${key}" || true
    if gpg --batch --list-keys "${key}" > /dev/null 2>&1; then
      return 0
    fi
  done

  return 1
}

# docker names architectures the way go does; apk and the toolchain use the kernel's names
case "${TARGETARCH}" in
  amd64) TARGET_APK_ARCH="x86_64" ;;
  arm64) TARGET_APK_ARCH="aarch64" ;;
  *) echo "no unbound build is set up for ${TARGETARCH}" >&2; exit 1 ;;
esac

UNBOUND_RELEASE="https://nlnetlabs.nl/downloads/unbound"
UNBOUND_TARBALL="unbound-${UNBOUND_VERSION}.tar.gz"

TARGET_TRIPLE="${TARGET_APK_ARCH}-alpine-linux-musl"
BUILD_PACKAGES="clang curl gnupg lld llvm make pkgconf protobuf-c-compiler"
SYSROOT_PACKAGES="expat-dev gcc hiredis-dev libevent-dev linux-headers musl-dev nghttp2-dev openssl-dev protobuf-c-dev"

echo "**** install build packages ****"
# shellcheck disable=SC2086 # the package lists are deliberately word split.
apk add --no-cache ${BUILD_PACKAGES}

echo "**** create ${TARGET_TRIPLE} sysroot ****"
mkdir -p /tmp/keys
for key in /etc/apk/keys/* "/usr/share/apk/keys/${TARGET_APK_ARCH}"/*; do
  cp "${key}" /tmp/keys/
done
# shellcheck disable=SC2086 # as above.
apk add --no-cache --arch "${TARGET_APK_ARCH}" --root /sysroot --initdb --no-scripts --keys-dir /tmp/keys \
  --repositories-file /etc/apk/repositories ${SYSROOT_PACKAGES}

cd /tmp

GNUPGHOME="$(mktemp -d)"
export GNUPGHOME

echo "**** download root hints ****"
mkdir -p /out/etc/unbound
curl -fsS --retry 3 -o /out/etc/unbound/root.hints https://www.internic.net/domain/named.cache

echo "**** build unbound ****"
if ! recv_key "${UNBOUND_KEY}"; then
  echo "no keyserver returned a usable copy of the unbound signing key ${UNBOUND_KEY}" >&2
  exit 1
fi
curl -fsSLO "${UNBOUND_RELEASE}/${UNBOUND_TARBALL}"
curl -fsSLO "${UNBOUND_RELEASE}/${UNBOUND_TARBALL}.asc"
gpg --batch --verify "${UNBOUND_TARBALL}.asc" "${UNBOUND_TARBALL}"
gpgconf --kill all
tar -xzf "${UNBOUND_TARBALL}"
cd "unbound-${UNBOUND_VERSION}"
export PKG_CONFIG_SYSROOT_DIR="/sysroot"
export PKG_CONFIG_LIBDIR="/sysroot/usr/lib/pkgconfig:/sysroot/usr/share/pkgconfig"
./configure \
  --build="$(clang -dumpmachine)" \
  --host="${TARGET_TRIPLE}" \
  --prefix=/usr \
  --sysconfdir=/etc \
  --localstatedir=/var \
  --with-username=abc \
  --with-run-dir="" \
  --with-pidfile="" \
  --with-rootkey-file=/usr/share/dnssec-root/trusted-key.key \
  --with-ssl=/sysroot/usr \
  --with-libevent=/sysroot/usr \
  --with-libexpat=/sysroot/usr \
  --with-libhiredis=/sysroot/usr \
  --with-libnghttp2=/sysroot/usr \
  --with-protobuf-c=/sysroot/usr \
  --with-pthreads \
  --enable-pie \
  --enable-relro-now \
  --enable-dnstap \
  --enable-subnet \
  --enable-cachedb \
  --disable-static \
  --disable-rpath \
  --disable-dsa \
  --disable-ghost \
  --without-pythonmodule \
  --without-pyunbound \
  CC="clang --target=${TARGET_TRIPLE} --sysroot=/sysroot -fuse-ld=lld" \
  LD="ld.lld" \
  AR="$(command -v llvm-ar)" \
  NM="llvm-nm" \
  RANLIB="llvm-ranlib" \
  STRIP="llvm-strip"
make -j"$(nproc)"
make install DESTDIR=/out
rm -rf /out/usr/include /out/usr/lib/pkgconfig /out/usr/lib/*.la /out/usr/share

# unbound-control-setup is a shell script; everything else installed is elf
ELF_FILES=""
for file in /out/usr/sbin/* /out/usr/lib/libunbound.so.*; do
  if [ ! -L "${file}" ] && llvm-readelf -h "${file}" > /dev/null 2>&1; then
    ELF_FILES="${ELF_FILES} ${file}"
  fi
done
# shellcheck disable=SC2086 # the file list is deliberately word split.
llvm-strip --strip-unneeded ${ELF_FILES}

echo "**** resolve runtime libraries ****"
# The shared libraries unbound links against, other than its own, as apk so: dependencies, so the image installs
# whichever packages provide them on its base.
mkdir -p /deps
# shellcheck disable=SC2086 # as above.
llvm-readelf -d ${ELF_FILES} | sed -nE 's/.*\(NEEDED\).*\[(.+)\]$/\1/p' | sort -u |
  while read -r soname; do
    [ -e "/out/usr/lib/${soname}" ] || echo "so:${soname}"
  done > /deps/runtime
EOF

FROM ${BASE_IMAGE}

# set version label
ARG build_date
ARG version
LABEL build_date="${build_date}"
LABEL version="${version}"
LABEL maintainer="Nightah"

SHELL ["/bin/ash", "-euo", "pipefail", "-c"]

# copy local files
COPY --link root/ /
COPY --link --from=build /out/ /

# install runtime packages and refresh the root trust anchor
RUN --mount=type=bind,from=build,source=/deps,target=/deps <<'EOF'
set -euo pipefail

xargs apk add --no-cache bind-tools dnssec-root < /deps/runtime
# unbound-anchor exits non-zero whenever it had to update the anchor
/usr/sbin/unbound-anchor -a /usr/share/dnssec-root/trusted-key.key || true
EOF

# ports, volumes and healthcheck
EXPOSE 53 53/udp
VOLUME /config
HEALTHCHECK CMD dig @127.0.0.1 || exit 1

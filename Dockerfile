FROM antilax3/alpine

# set version label
ARG build_date
ARG version
LABEL build_date="${build_date}"
LABEL version="${version}"
LABEL maintainer="Nightah"

# copy local files
COPY root/ /

# install packages
RUN \
echo "**** install build packages ****" && \
apk add --no-cache --virtual=build-dependencies \
    curl && \
echo "**** install runtime packages ****" && \
apk add --no-cache \
    bind-tools \
    musl \
    unbound && \
echo "**** setup unbound ****" && \
    curl -fs --retry 3 -o /etc/unbound/root.hints https://www.internic.net/domain/named.cache && \
    /usr/sbin/unbound-anchor -a /usr/share/dnssec-root/trusted-key.key | true && \
echo "**** cleanup ****" && \
apk del --purge \
    build-dependencies && \
rm -rf \
    /tmp/*

# ports, volumes and healthcheck
EXPOSE 53 53/udp
VOLUME /config
HEALTHCHECK CMD dig @127.0.0.1 || exit 1
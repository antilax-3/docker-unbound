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
echo "**** install runtime packages ****" && \
apk add --no-cache \
    bind-tools \
    musl \
    unbound && \
echo "**** setup unbound ****" && \
/usr/sbin/unbound-anchor -a /defaults/trusted-key.key | true

# ports, volumes and healthcheck
EXPOSE 53 53/udp
VOLUME /config
HEALTHCHECK CMD dig @127.0.0.1 || exit 1
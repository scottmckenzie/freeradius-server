ARG from=alpine:3.24
FROM ${from} AS build

#
#  Install build tools
#
RUN apk update
RUN apk add git gcc make

#
#  Create build directory
#
RUN mkdir -p /usr/local/src/repositories/freeradius-server
WORKDIR /usr/local/src/repositories/freeradius-server/

#
#  Shallow clone the FreeRADIUS repository
#
ARG FREERADIUS_RELEASE
ARG FREERADIUS_REPOSITORY
RUN git clone --depth 1 --branch ${FREERADIUS_RELEASE} ${FREERADIUS_REPOSITORY} .

#
#  Install build dependencies
#
# essential
RUN apk add libc-dev talloc-dev
RUN apk add openssl openssl-dev
RUN apk add linux-headers
# general
RUN apk add pcre-dev libidn-dev krb5-dev samba-dev curl-dev json-c-dev
RUN apk add openldap-dev unbound-dev
# languages
RUN apk add ruby-dev perl-dev python3-dev
# databases
RUN apk add hiredis-dev libmemcached-dev gdbm-dev
# sql
RUN apk add postgresql-dev mariadb-dev unixodbc-dev sqlite-dev

#
#  Build the server
#
RUN ./configure --prefix=/opt
RUN make -j"$(nproc)"
RUN make install
RUN rm /opt/lib/*.a

#
#  Clean environment and run the server
#
FROM ${from}
COPY --from=build /opt /opt

#
# These are needed for the server to start.
#  The server links against OpenSSL (built with openssl-dev above);
#  libssl/libcrypto come in as dependencies of the packages below.
#
RUN apk add --no-cache talloc pcre libwbclient tzdata \
    \
#
#  Libraries that are needed dependent on which modules are used
#  Some of these (especially the languages) are huge. A reasonable
#  selection has been enabled here. If you use modules needing
#  other dependencies then install any others required in your
#  local Dockerfile.
#
    && apk add --no-cache libcurl json-c libldap hiredis sqlite-libs \
#RUN apk add libidn krb5
#RUN apk add unbound-libs
#RUN apk add ruby-libs perl python3-dev
#RUN apk add libmemcached gdbm
#RUN apk add postgresql-dev mariadb-dev unixodbc-dev
    \
    && ln -s /opt/etc/raddb /etc/raddb \
    && addgroup -S radius \
    && adduser -S -D -H -G radius -h /opt/var/log/radius -s /sbin/nologin radius

WORKDIR /
COPY scripts/docker-entrypoint.sh docker-entrypoint.sh
RUN chmod +x docker-entrypoint.sh

#
#  Customise the stock config in place rather than shipping a copy of
#  it, so it tracks each FreeRADIUS release:
#    - remove inner-tunnel
#    - enable the "rewrite_called_station_id" policy, which creates the
#      Called-Station-MAC and Called-Station-SSID attributes
#    - drop privileges to radius:radius after startup
#  Each grep fails the build if upstream changes the line being edited.
#
RUN rm /opt/etc/raddb/sites-enabled/inner-tunnel \
    && sed -i 's/^#\(\trewrite_called_station_id\)$/\1/' \
        /opt/etc/raddb/sites-available/default \
    && grep -q '^	rewrite_called_station_id$' \
        /opt/etc/raddb/sites-available/default \
    && sed -i -e 's/^#\(\tuser = radius\)$/\1/' \
        -e 's/^#\(\tgroup = radius\)$/\1/' /opt/etc/raddb/radiusd.conf \
    && grep -q '^	user = radius$' /opt/etc/raddb/radiusd.conf \
    && grep -q '^	group = radius$' /opt/etc/raddb/radiusd.conf \
    && chgrp -R radius /opt/etc/raddb \
    && chmod -R g+rX,o-rwx /opt/etc/raddb \
    && install -d -o radius -g radius /opt/var/run/radiusd \
    && chown -R radius:radius /opt/var/log/radius

EXPOSE 1812/udp 1813/udp
ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["radiusd"]

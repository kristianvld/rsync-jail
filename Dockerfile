# syntax=docker/dockerfile:1
FROM alpine:3.24@sha256:28bd5fe8b56d1bd048e5babf5b10710ebe0bae67db86916198a6eec434943f8b

# Install OpenSSH and rsync. Then create a /jail template directory that
# all users will have, with only access to /bin/sh and /usr/bin/rsync (with libraries).
# hadolint ignore=DL3018
RUN apk add --no-cache iptables jq openssh rsync && \
    apk del --purge apk-tools && \
    rm -rf /var/cache/apk/* /tmp/* /var/tmp/* /usr/share/man/* /usr/share/doc/* && \
    mkdir -p /jail/bin/ /jail/usr/bin/ /jail/usr/lib/ /jail/lib/ && \
    cp -aL /bin/sh /jail/bin/sh && \
    cp -aL /usr/bin/rsync /jail/usr/bin/rsync && \
    cp -aL /usr/lib/libacl.so.1 /jail/usr/lib/ && \
    cp -aL /usr/lib/libpopt.so.0 /jail/usr/lib/ && \
    cp -aL /usr/lib/liblz4.so.1 /jail/usr/lib/ && \
    cp -aL /usr/lib/libzstd.so.1 /jail/usr/lib/ && \
    cp -aL /usr/lib/libxxhash.so.0 /jail/usr/lib/ && \
    cp -aL /usr/lib/libz.so.1 /jail/usr/lib/ && \
    cp -aL /lib/ld-musl-*.so.1 /jail/lib/

# Minimal SSH config
COPY sshd_config /etc/ssh/sshd_config

# Add entrypoint script that creates users and starts SSH server
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD ps | grep '[s]shd' >/dev/null || exit 1

# sshd must start as root so it can authenticate users, chroot sessions, and bind port 22.
# hadolint ignore=DL3002
USER root
EXPOSE 22
ENTRYPOINT ["/entrypoint.sh"]

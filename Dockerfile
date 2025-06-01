FROM alpine:latest

# Install OpenSSH and rsync. Then create a /jail template directory that
# all users will have, with only access to /bin/sh and /usr/bin/rsync (with libraries).
RUN apk add --no-cache jq openssh rsync && \
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

USER root
EXPOSE 22
ENTRYPOINT ["/entrypoint.sh"]
